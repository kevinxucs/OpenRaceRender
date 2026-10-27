# Receive files over a local network (F32)

Open **File → Receive files over WiFi / network…**, choose a destination and click **Start receiving**. On a device connected to the same trusted local network, open one of the pairing links in its browser. Select the exported telemetry and corresponding video files and choose **Send selected files**. Keep the page open. When complete, the Mac lists the saved files and offers **Add to current project**, **Create new session**, or **Show files in Finder**. Creating a new session uses the existing unsaved-change prompt. After import, check synchronization and choose a template in the library.

The default destination is `~/Library/Application Support/OpenRaceRender/Received`. Each completed transfer gets a new `Received-…` subfolder. Originals and existing destination files are not replaced. The receiver starts only on request and stops after completion or when its window closes. Stopping before completion deletes this transfer's staging folder. Importing is separate from receiving, so already completed files remain available even if import fails or is undone.

This implementation uses its own documented browser/HTTP protocol. **TrackAddict's built-in WiFi device scan and proprietary transfer protocol are not implemented or claimed compatible.** You can send files previously exported from TrackAddict through this page, or use its documented USB/file-sharing export and normal Add inputs. RaceRender's public guides describe its discovery workflow but do not specify the wire messages; no real sender or packet fixture was available, and native UI access remains unavailable. Native TrackAddict discovery/transfer is still outstanding under F32.

## Transfer behavior

Uploads stream to disk in at most 64 KiB receive buffers. A private staging folder is moved into place only after the sender finishes. There is no file-download/list endpoint, filesystem path selection over the network, project execution, permanent background listener, or outgoing network service. Each receive session has a fresh random pairing token. Anyone with that link can upload while receiving. Traffic uses HTTP, so use a trusted local network. macOS may ask for Local Network access when starting the receiver; nothing requests it at app launch.

Up to four connections, 64 files, 64 GiB per file and 128 GiB per transfer are accepted. Requests idle for 60 seconds are closed and their incomplete file removed. Supported telemetry, video, audio and image extensions are accepted; remote RRP/project files and unknown executable formats are refused. Filenames must be single path components, at most 255 UTF-8 bytes, with no control characters. Case/Unicode-equivalent collisions, traversal, duplicate HTTP fields, chunked bodies, inconsistent lengths and oversized headers are rejected. There is no cross-session resume; restart receiving to retry a failed batch. Completed raw files are not automatically trusted to be decodable media; import reports format errors normally.

## Open client protocol

The receiver chooses an ephemeral TCP port and shows its active IPv4 links. It does not advertise a RaceRender/TrackAddict service. These endpoints require the exact token from the pairing URL:

1. `GET /?token=TOKEN` returns the self-contained upload page.
2. `PUT /upload?token=TOKEN&name=URL_ENCODED_FILENAME` sends one raw file with a positive `Content-Length`. Repeat sequentially for each file.
3. `POST /finish?token=TOKEN`, with an empty body, publishes the batch. The receiver acknowledges completion and stops.

A successful response is HTTP 200. Invalid requests return 400 with a plain-text explanation and close the connection. The browser page uses `fetch` with a `File` body and requires the browser to send its known length. Clients must not use HTTP chunked encoding or multipart form encoding. Example, while the receiver is running:

```sh
curl --fail -X PUT --data-binary @session.csv \
  'http://MAC_ADDRESS:PORT/upload?token=TOKEN&name=session.csv'
curl --fail -X POST 'http://MAC_ADDRESS:PORT/finish?token=TOKEN'
```

## Validation and limits

Tests exercise actual loopback HTTP page retrieval, bad tokens, multi-buffer upload and completion, exact received bytes and telemetry decoding. Protocol/storage tests cover ambiguous framing, traversal/control characters, size limits, case/Unicode collisions, partial cleanup, private staging and preservation of existing files. Editor tests cover add/new-session import, current objects/marks, missing receipts and Undo without file deletion. All networking tests bind only to loopback. Actual phone-browser use, firewall/macOS permission prompts and native TrackAddict transfer are not verified because CUA continues to return `cgWindowNotFound`.

References: [RaceRender receive workflow](https://racerender.com/RR3/docs/Transfer.html), [TrackAddict export instructions](https://racerender.com/TrackAddict/docs/GettingStarted.html), [Apple NWListener](https://developer.apple.com/documentation/network/nwlistener), and [requiredLocalEndpoint](https://developer.apple.com/documentation/network/nwparameters/requiredlocalendpoint).
