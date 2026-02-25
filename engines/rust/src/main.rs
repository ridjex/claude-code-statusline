mod background;
mod cache;
mod config;
mod format;
mod git;
mod render;
mod session;

use std::io;
use std::path::Path;

fn main() {
    // Panic hook: never crash the render cycle
    std::panic::set_hook(Box::new(|_| {
        let _ = io::Write::write_all(&mut io::stdout(), b"\n\n");
    }));

    let result = std::panic::catch_unwind(|| {
        let args: Vec<String> = std::env::args().skip(1).collect();
        let cfg = config::load(&args);

        if cfg.show_version {
            let version = env!("CARGO_PKG_VERSION");
            let _ = io::Write::write_all(
                &mut io::stdout(),
                format!("statusline {} (rust)\n", version).as_bytes(),
            );
            return;
        }

        if cfg.show_help {
            print_help();
            return;
        }

        // Internal mode: refresh model cache
        if cfg.internal_refresh_models {
            background::refresh_model_cache(
                &cfg.internal_session_id,
                &cfg.internal_transcript_path,
            );
            return;
        }

        let sess = session::parse(io::stdin());

        // Render output
        let output = render::render(&sess, &cfg);
        let _ = io::Write::write_all(&mut io::stdout(), output.as_bytes());

        // Fire-and-forget background jobs
        let session_id = if !sess.transcript_path.is_empty() {
            let base = Path::new(&sess.transcript_path)
                .file_name()
                .map(|f| f.to_string_lossy().to_string())
                .unwrap_or_default();
            base.strip_suffix(".jsonl").unwrap_or(&base).to_string()
        } else {
            String::new()
        };

        background::spawn_cumulative_stats(&sess.workspace.project_dir);
        if !session_id.is_empty() && !sess.transcript_path.is_empty() {
            background::spawn_model_refresh(&session_id, &sess.transcript_path);
        }
    });

    if result.is_err() {
        let _ = io::Write::write_all(&mut io::stdout(), b"\n\n");
    }
}

fn print_help() {
    let _ = io::Write::write_all(
        &mut io::stderr(),
        b"Usage: statusline [OPTIONS]\n\
          Reads JSON from stdin, outputs formatted status bar.\n\
          \n\
          Options:\n\
          \x20 --no-model       Hide model name\n\
          \x20 --no-model-bars  Hide model mix bars\n\
          \x20 --no-context     Hide context window bar\n\
          \x20 --no-cost        Hide session cost\n\
          \x20 --no-duration    Hide duration\n\
          \x20 --no-git         Hide git branch/status\n\
          \x20 --no-diff        Hide lines added/removed\n\
          \x20 --no-line2       Hide entire second line\n\
          \x20 --no-tokens      Hide token counts\n\
          \x20 --no-speed       Hide throughput (tok/s)\n\
          \x20 --no-cumulative  Hide cumulative costs\n\
          \x20 --no-color       Disable ANSI colors\n\
          \x20 --version        Show version\n\
          \x20 --help           Show this help\n\
          \n\
          Config precedence: CLI args > env vars > ~/.claude/statusline.env > defaults (all on)\n",
    );
}
