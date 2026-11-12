//! Whether an AppKit inventory that skipped records is still complete.

use super::{inventory_error, records};
use agent_desktop_core::AdapterError;

pub(crate) fn require_complete(skipped: &[serde_json::Value]) -> Result<(), AdapterError> {
    PROCESSLESS_RECORDS.with(|last| require_complete_with(skipped, &mut last.borrow_mut()))
}

thread_local! {
    /// The processless pids that the previous inventory read on this thread skipped.
    static PROCESSLESS_RECORDS: std::cell::RefCell<Option<Vec<i64>>> =
        const { std::cell::RefCell::new(None) };
}

/// An inventory that skipped records is incomplete, except for records that
/// have no process at all (`pid <= 0`, such as a phantom AppKit entry for an
/// app that is not running) and that repeat unchanged since the previous read.
/// No command can act on such a record, and treating it as churn would make
/// every inventory-dependent command time out until the phantom disappears.
pub(super) fn require_complete_with(
    skipped: &[serde_json::Value],
    last: &mut Option<Vec<i64>>,
) -> Result<(), AdapterError> {
    let mut processless = Vec::new();
    let mut other = false;
    for record in skipped {
        match processless_pid(record) {
            Some(pid) => processless.push(pid),
            None => other = true,
        }
    }
    processless.sort_unstable();
    let repeated = last.as_ref() == Some(&processless);
    *last = Some(processless);
    if skipped.is_empty() || (!other && repeated) {
        return Ok(());
    }
    Err(records::with_skipped(
        inventory_error("AppKit application inventory skipped records"),
        skipped,
    ))
}

fn processless_pid(record: &serde_json::Value) -> Option<i64> {
    if record["field"] != "pid" {
        return None;
    }
    record["pid"].as_i64().filter(|pid| *pid <= 0)
}
