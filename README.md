# Tidbyt: NYC Subway Zoom

A Tidbyt app that shows the next arrivals at a given subway stop.

<img src="https://github.com/user-attachments/assets/d78d15a9-c360-4ab7-9958-4089ceea1efe" style="width: 600px; image-rendering: pixelated; image-rendering: -moz-crisp-edges;
image-rendering: crisp-edges;" />

It's like the builtin NYC Subway app, but with the ability to show **eight**
upcoming arrivals rather than only two.

## Usage

Currently only available as a Tidbyt private app. You'll likely want to
adjust the code first to choose your own stop.

Then, to push once to your device:

```
./bin/push
```

To upload as a private app:

```
./bin/upload
```

## Contributing

PR's welcome! I'd particularly appreciate a PR that adds support for
dynamic configuration of the stop, so that you don't need to recompile the
app to change the displayed stop.
