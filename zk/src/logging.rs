use log::{Level, Metadata, Record};
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Once,
};

struct SimpleLogger;

static LOGGER: SimpleLogger = SimpleLogger;
static LOGGER_INIT: Once = Once::new();

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum LoggerMode {
    Debug = 1,
    Info = 2,
    Error = 3,
    Danger = 4,
}

static LOG_LEVEL: AtomicUsize = AtomicUsize::new(LoggerMode::Debug as usize);

fn current_level() -> LoggerMode {
    match LOG_LEVEL.load(Ordering::Relaxed) {
        1 => LoggerMode::Debug,
        2 => LoggerMode::Info,
        3 => LoggerMode::Error,
        4 => LoggerMode::Danger,
        _ => LoggerMode::Debug,
    }
}

impl log::Log for SimpleLogger {
    fn enabled(&self, metadata: &Metadata) -> bool {
        let current = current_level();

        match metadata.level() {
            Level::Debug | Level::Trace => current <= LoggerMode::Debug,
            Level::Info => current <= LoggerMode::Info,
            Level::Warn => current <= LoggerMode::Error,
            Level::Error => current <= LoggerMode::Danger,
        }
    }

    fn log(&self, record: &Record) {
        if !self.enabled(record.metadata()) {
            return;
        }

        println!(
            "[{}] [{}] {}",
            record.level(),
            record.target(),
            record.args()
        );
    }

    fn flush(&self) {}
}

pub fn init_logger() {
    LOGGER_INIT.call_once(|| {
        let _ = log::set_logger(&LOGGER);

        // Must allow everything globally.
        log::set_max_level(log::LevelFilter::Trace);
    });
}

pub fn enable_logging(level: u8) {
    init_logger();

    let mode = match level {
        1 => LoggerMode::Debug,
        2 => LoggerMode::Info,
        3 => LoggerMode::Error,
        4 => LoggerMode::Danger,
        _ => LoggerMode::Debug,
    };

    LOG_LEVEL.store(mode as usize, Ordering::Relaxed);
}

pub fn disable_logging() {
    init_logger();
    LOG_LEVEL.store(usize::MAX, Ordering::Relaxed);
}
