# Greppit for the desktop

A Mac app (Tauri 2) whose window shows https://greppit.app. It isn't a
separate frontend: it loads the live site, so it looks exactly like it and
picks up every deploy with no rebuild.

- **Login:** the app keeps its own login (in its own web storage), apart
  from your browser's.
- **Links** to other sites open in your default browser; iframes inside
  documents (Desmos and the like) still load in place.
- **Menu:** View → Reload (Cmd-R), View → Go to greppit.app (Cmd-Shift-H).
- **Window** size and position are remembered between launches.
- The page gets no access to Tauri's APIs (`src-tauri/capabilities/default.json`
  grants nothing).

## Build

Needs Rust 1.90 or newer and Node.

    cd desktop
    npm install
    npm run build      # → src-tauri/target/release/bundle/macos/Greppit.app

Drag `Greppit.app` into /Applications. It isn't signed with an Apple
developer certificate; a copy built on this Mac opens normally, but one
copied from elsewhere needs right-click → Open the first time.

`npm run dev` runs it without bundling.

## Files

- `src-tauri/src/lib.rs`: the window, the menu, and the link handling.
- `src-tauri/tauri.conf.json`: app name, identifier `app.greppit.desktop`, icons.
- `src-tauri/icons/icon.svg`: the icon source (the site's scissors favicon);
  regenerate the rest with `npx tauri icon src-tauri/icons/icon-source.png -o src-tauri/icons`
  after rendering it with `rsvg-convert -w 1024 -h 1024 icon.svg -o icon-source.png`.
