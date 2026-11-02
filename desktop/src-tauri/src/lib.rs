//! Greppit for the desktop: a window that shows https://greppit.app.
//!
//! The page is the live site, so it looks and behaves exactly like it and
//! picks up every deploy. It gets no access to Tauri's APIs (see
//! capabilities/default.json). Links to other sites open in the default
//! browser, so the window always stays greppit.

use tauri::menu::{Menu, MenuItemBuilder, SubmenuBuilder};
use tauri::webview::{DownloadEvent, NewWindowResponse};
use tauri::{Manager, Url, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_opener::OpenerExt;

const HOME: &str = "https://greppit.app";

// Runs in the main frame only, so iframes in documents (Desmos and the
// like) still load. A click on a link to another site becomes a
// window.open, which on_new_window below sends to the browser.
const LINK_SCRIPT: &str = r#"
document.addEventListener('click', (e) => {
  if (e.defaultPrevented || e.button !== 0) return;
  const a = e.target.closest && e.target.closest('a[href]');
  if (!a) return;
  const url = new URL(a.href, location.href);
  if ((url.protocol === 'http:' || url.protocol === 'https:') && url.host !== location.host) {
    e.preventDefault();
    window.open(url.href, '_blank');
  }
}, true);
"#;

fn is_web(url: &Url) -> bool {
    url.scheme() == "http" || url.scheme() == "https"
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_window_state::Builder::default().build())
        .menu(|app| {
            let reload = MenuItemBuilder::with_id("reload", "Reload")
                .accelerator("CmdOrCtrl+R")
                .build(app)?;
            let home = MenuItemBuilder::with_id("home", "Go to greppit.app")
                .accelerator("CmdOrCtrl+Shift+H")
                .build(app)?;
            Menu::with_items(
                app,
                &[
                    &SubmenuBuilder::new(app, "Greppit")
                        .about(None)
                        .separator()
                        .services()
                        .separator()
                        .hide()
                        .hide_others()
                        .show_all()
                        .separator()
                        .quit()
                        .build()?,
                    &SubmenuBuilder::new(app, "Edit")
                        .undo()
                        .redo()
                        .separator()
                        .cut()
                        .copy()
                        .paste()
                        .select_all()
                        .build()?,
                    &SubmenuBuilder::new(app, "View")
                        .item(&reload)
                        .item(&home)
                        .separator()
                        .fullscreen()
                        .build()?,
                    &SubmenuBuilder::new(app, "Window")
                        .minimize()
                        .maximize()
                        .separator()
                        .close_window()
                        .build()?,
                ],
            )
        })
        .on_menu_event(|app, event| {
            if let Some(window) = app.get_webview_window("main") {
                match event.id().as_ref() {
                    "reload" => {
                        let _ = window.eval("location.reload()");
                    }
                    "home" => {
                        let _ = window.navigate(HOME.parse().unwrap());
                    }
                    _ => {}
                }
            }
        })
        .setup(|app| {
            let opener = app.handle().clone();
            let revealer = app.handle().clone();
            WebviewWindowBuilder::new(app, "main", WebviewUrl::External(HOME.parse()?))
                .title("Greppit")
                .inner_size(1200.0, 800.0)
                .min_inner_size(600.0, 400.0)
                .initialization_script(LINK_SCRIPT)
                .on_new_window(move |url, _features| {
                    if is_web(&url) {
                        let _ = opener.opener().open_url(url.as_str(), None::<&str>);
                    }
                    NewWindowResponse::Deny
                })
                // Without a handler the webview cancels downloads, so
                // Export did nothing. They go to ~/Downloads (as
                // "name (1).ext" rather than overwriting), and the saved
                // file is shown in Finder, since there's no download bar.
                .on_download(move |_webview, event| {
                    if let DownloadEvent::Finished { path: Some(path), success: true, .. } = event {
                        let _ = revealer.opener().reveal_item_in_dir(path);
                    }
                    true
                })
                .build()?;
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running Greppit");
}
