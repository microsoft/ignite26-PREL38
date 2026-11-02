# Published lab guide backup

`prel38-skillable-guide.md` is a byte-for-byte copy of the full lab guide as published in Skillable on November 2, 2026 (SHA-256 `7b9a5d6cca3316d71c14e9b2b1b6f5d904a51b12937b46b388bac8710e3150de`). Skillable remains the source of truth; this copy exists so the Part 2 corrections can be reapplied if the live guide is lost or overwritten.

It uses Skillable markdown: images are referenced as `!IMAGE [alt](instructions<set-id>/<file>.png)` and resolve only inside Skillable. `images/` holds the five Part 2 screenshots added in this revision. The other screenshots were uploaded earlier, some by other authors, and live only in Skillable.

## Reapply the guide

Other authors edit other parts of the same guide, so don't paste this file over the live copy without comparing first.

1. Launch a fresh instance of the development lab and open **Settings > Edit Instructions**.
2. Copy the live guide out and diff it against this file. Keep newer edits from other authors; apply only the Part 2 corrections you need.
3. Upload any missing screenshots from `images/`, save, reload, and confirm the saved text matches what you intended.
4. Launch another fresh instance and check that the guide, screenshots, and **Resources > GitHub sign-in** entry appear.

## Resources tab entry

**Resources > GitHub sign-in** isn't part of the guide markdown; it's defined on the development lab profile under **Edit > Resources**. Recreate it with these values if it's missing:

- **Name:** `GitHub sign-in`
- **Type:** External Link
- **URL:** `https://github.com/enterprises/skillable-events/sso`
- **Description:**

  ```text
  Inside the VM, sign in to GitHub only through single sign-on (SSO) with your lab Azure account. Don't use the github.com Sign in form; it says Incorrect username or password. Browser: go to https://github.com/enterprises/skillable-events/sso, select Continue, and use the Username and TAP from the Azure Portal card. CLI: run gh auth login; pick GitHub.com, HTTPS, Yes, Login with a web browser. Note the code, press Enter, sign in the same way, enter the code, Authorize github. Check gh auth status
  ```
