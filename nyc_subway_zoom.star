# ==> Configuration.

# The URL of the GTFS feed.
# For the NYC MTA feeds, see: https://api.mta.info/#/subwayRealTimeFeeds
GTFS_FEED_URL = "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs"

# The ID of the stop to watch.
# For the NYC MTA, see: http://web.mta.info/developers/data/nyct/subway/google_transit.zip
STOP_ID = b"123S"

# The color of the bullet to use for arrivals.
BULLET_COLOR = "#ee352e"

# Number of hardcoded iterations to simulate an infinite loop, since Starlark
# doesn't support infinite loops. Used for decoding protobuf messages and such,
# which can support an arbitrary number of fields, etc.
MAX_ITERATIONS = 2 << 20

# ==> Entrypoint.

load("render.star", "render")
load("http.star", "http")
load("time.star", "time")

def main():
    feed = gtfs_get_feed(GTFS_FEED_URL)
    arrivals = gtfs_get_upcoming_arrivals(STOP_ID, feed)
    return render.Root(render_arrivals(arrivals))

# ==> Rendering.

def render_arrivals(arrivals):
    arrivals = [arrivals[:4], arrivals[4:]]
    return render.Row(
        children = [
            render.Padding(
                child = render.Column(
                    children = [render_arrival(arrival) for arrival in arrivals],
                ),
                pad = (1, 0, 2, 0),
            )
            for arrivals in arrivals
        ],
        expanded = True,
        main_align = "space_between",
    )

def render_arrival(arrival):
    return render.Row(
        children = [
            render_bullet(arrival.route_id),
            render.Padding(child = render_eta(arrival.eta), pad = (2, 0, 0, 0)),
        ],
    )

def render_bullet(route):
    return render.Circle(
        color = BULLET_COLOR,
        diameter = 7,
        child = render.Text(str(route), font = "tom-thumb"),
    )

def render_eta(eta):
    # Truncating rounding is useful as we want to miss in the "arriving too
    # soon" direction.
    eta = int((eta - time.now()).minutes)
    if eta < 1:
        return render.Text("now", font = "tb-8", color = "#ffa500")
    else:
        return render.Text("{}m".format(eta), font = "tb-8")

# ==> GTFS-specific decoding.
#
# We hand roll a protobuf decoder here because Starlark doesn't have built-in
# support for parsing protobufs (nor a package system). The alternative would be
# to run a service somewhere that converts the protobuf API to a JSON API, but
# that would be annoying to maintain. While this was painful to write it is
# likely to continue to operate without maintenance for the foreseeable future.

# Field number constants. Extracted from https://gtfs.org/documentation/realtime/proto
# on 24 November 2024.
FEED_MESSAGE_ENTITY_FIELD_NUMBER = 2
FEED_ENTITY_TRIP_UPDATE_FIELD_NUMBER = 3
TRIP_UPDATE_TRIP_FIELD_NUMBER = 1
TRIP_UPDATE_STOP_TIME_UPDATE_FIELD_NUMBER = 2
TRIP_DESCRIPTOR_ROUTE_ID_FIELD_NUMBER = 5
STOP_TIME_UPDATE_STOP_ID_FIELD_NUMBER = 4
STOP_TIME_UPDATE_ARRIVAL_FIELD_NUMBER = 2
STOP_TIME_EVENT_ARRIVAL_TIME_FIELD_NUMBER = 2

def gtfs_get_feed(url):
    return http.get(url, ttl_seconds = 5).bytes()

def gtfs_get_upcoming_arrivals(stop_id, reader):
    upcoming_arrivals = []
    feed_message, _ = proto_decode_message(reader)
    for feed_entity in feed_message.get(FEED_MESSAGE_ENTITY_FIELD_NUMBER, []):
        feed_entity, _ = proto_decode_message(feed_entity)
        for trip_update in feed_entity.get(FEED_ENTITY_TRIP_UPDATE_FIELD_NUMBER, []):
            trip_update, _ = proto_decode_message(trip_update)
            trip_descriptors = trip_update.get(TRIP_UPDATE_TRIP_FIELD_NUMBER, [""])
            trip_descriptor, _ = proto_decode_message(trip_descriptors[0])
            route_ids = trip_descriptor.get(TRIP_DESCRIPTOR_ROUTE_ID_FIELD_NUMBER, [""])
            route_id = route_ids[0]
            for stop_time_update in trip_update.get(TRIP_UPDATE_STOP_TIME_UPDATE_FIELD_NUMBER, []):
                stop_time_update, _ = proto_decode_message(stop_time_update)
                stop_ids = stop_time_update.get(STOP_TIME_UPDATE_STOP_ID_FIELD_NUMBER, [])
                if stop_ids != [STOP_ID]:
                    continue
                arrivals = stop_time_update.get(STOP_TIME_UPDATE_ARRIVAL_FIELD_NUMBER, [""])
                arrival, _ = proto_decode_message(arrivals[0])
                arrival_times = arrival.get(STOP_TIME_EVENT_ARRIVAL_TIME_FIELD_NUMBER, [0])
                arrival_time = time.from_timestamp(arrival_times[0])
                if arrival_time > time.now():
                    upcoming_arrivals.append(struct(route_id = route_id, eta = arrival_time))
    return sorted(upcoming_arrivals, key = lambda x: x.eta)

# ==> Generic Protobuf decoding.

PROTO_WIRE_TYPE_VARINT = 0
PROTO_WIRE_TYPE_I64 = 1
PROTO_WIRE_TYPE_LEN = 2
PROTO_WIRE_TYPE_SGROUP = 3
PROTO_WIRE_TYPE_EGROUP = 4
PROTO_WIRE_TYPE_I32 = 5

def proto_decode_message(reader):
    """Decode a single message from a protobuf reader.

    Returns a dict mapping field numbers to lists of field values. A required
    field will always appear in the output dict and its list will have exactly
    one value. Optional and repeated fields may or may not appear in the output
    dict. When an optional field appears, it will have exactly one value in its
    list. When a repeated field appears, it will have one or more values in its
    list.
    """
    out = dict()
    for _ in range(MAX_ITERATIONS):
        if len(reader) == 0:
            break
        field_number, field_value, reader = proto_decode_field(reader)
        if field_number not in out:
            out[field_number] = []
        out[field_number].append(field_value)
    return out, reader

def proto_decode_field(reader):
    varint, reader = proto_decode_varint(reader)
    field_number = varint >> 3
    wire_type = varint & 0x07
    if wire_type == PROTO_WIRE_TYPE_VARINT:
        field_value, reader = proto_decode_varint(reader)
    elif wire_type == PROTO_WIRE_TYPE_LEN:
        field_value, reader = proto_decode_len(reader)
        # WARNING: many other wire types ignored, as they do not appear in the
        # GTFS protobufs.

    else:
        fail("proto_decode_field: unknown wire type: {}".format(wire_type))
    return field_number, field_value, reader

def proto_decode_varint(reader):
    out = 0
    shift = 0
    for _ in range(MAX_ITERATIONS):
        byte, reader = proto_next_byte(reader)
        out += (byte & 0x7f) << shift
        shift += 7
        if (byte & 0x80) == 0:
            break
    return out, reader

def proto_decode_len(reader):
    len, reader = proto_decode_varint(reader)
    out = reader[:len]
    reader = reader[len:]
    return out, reader

def proto_next_byte(reader):
    out = ord(reader[0])
    reader = reader[1:]
    return out, reader
