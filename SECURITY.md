# Security Policy

Thank you for helping keep Peraviz safe.

Peraviz is an open-source real-time 3D DMX visualizer that works with MVR, GDTF, mesh assets, textures, archives, native code, and live network input. If you find a security issue, suspicious behavior, or anything that could put users, files, projects, or systems at risk, please report it responsibly.

## Reporting a security issue

Please do not open a public GitHub issue for security vulnerabilities.

Instead, send an email to:

**perastage.app@gmail.com**

Please include as much relevant information as possible:

- A clear description of the issue.
- Steps to reproduce it, if possible.
- The Peraviz version or commit affected.
- Your operating system.
- Any related files, logs, screenshots, or crash reports that may help understand the problem.
- Whether the issue affects imported files, extracted archives, live network input, rendering assets, installation, releases, crashes, or another part of the application.

If you are not sure whether something is a security issue, feel free to report it anyway.

## What to expect

After receiving a report, I will try to:

- Confirm that the report has been received.
- Review the issue as soon as possible.
- Ask for more details if needed.
- Work on a fix when the issue is confirmed.
- Credit the reporter if appropriate and if they want to be credited.

Please keep in mind that Peraviz is an independent open-source project, so response times may vary depending on availability and the complexity of the issue.

## Supported versions

Security fixes will generally focus on the latest public release of Peraviz.

If Peraviz has not yet published stable releases, security fixes will focus on the current `main` branch and the next available public build.

Older builds may not receive security updates unless the issue is especially important or easy to patch.

For the best experience and safety, users are encouraged to use the latest available version.

## Responsible disclosure

Please give reasonable time to investigate and fix the issue before sharing details publicly.

This helps protect users while the problem is being reviewed and corrected.

## Scope

Security reports may include, but are not limited to:

- Crashes caused by malformed MVR, GDTF, ZIP, 3DS, GLB, OBJ, texture, or related files.
- Unsafe archive extraction, path traversal, or unexpected file overwrite behavior.
- Problems with file paths, temporary files, generated assets, or cached data.
- Unexpected file creation, overwrite, or deletion.
- Issues caused by malformed or hostile live network input such as Art-Net, DMX-related packets, or future sACN input.
- Native crashes that may be exploitable or caused by malformed input.
- Issues related to installers, releases, downloaded assets, or bundled dependencies.
- Any behavior that could compromise a user's system, projects, files, or data.

General bugs, feature requests, compatibility issues, usability issues, and normal crashes that do not appear security-related should be reported using GitHub Issues instead.
