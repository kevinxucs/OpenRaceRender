# YouTube upload (F33)

Open **File → Upload video to YouTube…**. The previous completed export is selected when it exists; **Choose video…** selects another completed MP4/MOV/M4V/WebM file. Import a Google **Desktop app** OAuth client JSON, sign in through the system browser, and review the title, description, tags, category, audience and visibility. Visibility defaults explicitly to **Private**, and subscriber notifications default off. **Upload selected video** is the action that sends the video and metadata to YouTube. Opening this screen, importing credentials and signing in do not upload a video.

The export dialog also offers **Review a YouTube upload after rendering**. A successful render opens the same review screen. Failed exports and exports from a document that has since been replaced do not start this review. Rendering does not automatically transmit the output.

## Google setup

1. In your Google Cloud project, enable YouTube Data API v3 and configure its OAuth consent settings/test users as required by Google.
2. Create OAuth credentials with application type **Desktop app** and download its client JSON. The app accepts the `installed` configuration, including an optional client secret. Imported authorization/token endpoints are ignored; requests use Google's documented HTTPS endpoints.
3. Import that JSON in the upload screen and sign in. Select the intended Google account and YouTube channel in Google's browser flow. The app requests only `https://www.googleapis.com/auth/youtube.upload`; it does not request account/profile or channel-list scopes to display extra identity information.
4. Choose the intended audience and visibility, review the exact file/details, then upload. Google project settings, account/channel eligibility, quota and service policies still apply. No shared project credentials or API keys are bundled with this open-source app.

Passwords are entered only in Google's system-browser flow. Authorization uses an ephemeral IPv4 loopback callback, random state and SHA-256 PKCE. Wrong state, duplicate code/state parameters and unexpected callback hosts are rejected. Sign-in can be cancelled and times out after five minutes. No remote callback relay or embedded browser is used.

Client configuration, access/refresh tokens and pending upload state are stored in generic-password Keychain entries scoped to `org.openracerender.youtube`, keyed by the selected client. Nothing is stored in the project/template, repository or plaintext preferences. **Disconnect locally** deletes this client's local token/resume entry; it does not revoke Google-side access or delete uploaded videos. You can revoke access through [Google Account permissions](https://myaccount.google.com/permissions). Locally ad hoc signed development builds may cause macOS to ask for access to their own Keychain items after rebuilding; a consistent signing identity can improve continuity.

## Pause, resume and file safety

Uploads use the current YouTube Data API v3 resumable protocol, with 16 MiB chunks. Before sending bytes, a new resumable session is saved in Keychain. Resume first asks YouTube for its acknowledged byte range, then continues at the exact next byte. Network failures, HTTP 429 and 5xx responses use bounded retries and honor Retry-After. The app refreshes expiring authorization before subsequent requests. Other failures retain the resume state and show a diagnostic.

**Pause / cancel** cancels the active operation. Closing the screen also pauses it. Reopen the uploader to restore the saved file/metadata and **Resume upload**. If YouTube already completed the upload, its status response provides the existing video ID and no duplicate is created. An expired/invalid remote session requires explicitly discarding its local resume state and starting again. Discarding local state does not delete anything already accepted by YouTube.

The source file is never modified. Size, modification time and hashes of its first/last 64 KiB guard against uploading a changed file into a saved session. The engine reads at most one chunk plus its bounded responses, not the whole video. The editor checks for a playable video track and positive duration before creating a remote session. It accepts files up to 256 GB. Upload URLs are restricted to Google's documented HTTPS API upload hosts/paths; HTTP redirects are refused so authorization cannot follow an unexpected location.

After acceptance, the app links to the video. YouTube may continue processing it. There is no scheduling, thumbnail upload, playlist management, caption management, remote video deletion or account switching inside an active upload; these are outside this feature.

## Validation

Tests use original synthetic bytes or the app's original generated test video, mocked Google responses and an in-memory credential store. They verify PKCE against the published RFC vector, upload-only scope, form escaping, token refresh/scope refusal, actual loopback state/host/code handling, partial server acknowledgments after network/5xx errors, exact resumed byte slices, bounded no-progress retries, cancellation, unexpected-host/changed-file refusal, saved metadata, explicit upload, durable reopening, already-completed recovery, local disconnect and invalid/unfinished-file rejection. No real Google account was accessed and no user video was uploaded.

The complete suite passes 374 tests with the authorized local library/graphics services. Live Google OAuth, actual Keychain permission prompts, real YouTube uploads and native GUI comparisons remain unverified. No Google client credentials were supplied for a live test; UI automation remains unavailable (`cgWindowNotFound`). Users configure and authorize their own client through the review screen.

Primary references checked during implementation: [Google Desktop OAuth/PKCE](https://developers.google.com/identity/protocols/oauth2/native-app), [desktop loopback support](https://developers.google.com/identity/protocols/oauth2/resources/loopback-migration), [YouTube resumable protocol](https://developers.google.com/youtube/data/guides/using_resumable_upload_protocol), [videos.insert](https://developers.google.com/youtube/data/reference/rest/v3/videos/insert), and the locally mirrored RaceRender Create Video guide's uploader workflow. The implementation uses current v3 APIs and does not reuse RaceRender's obsolete GData upload endpoint.
