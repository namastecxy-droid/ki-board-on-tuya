//! Wire protocol (v1) shared between firmware and companion.
//!
//! Line-delimited JSON. See `../../../shared/protocol/protocol.md` for the
//! full spec. This module is pure (no Tauri / IO deps) so it stays unit-testable.

use serde_json::Value;

pub const PROTOCOL_VERSION: u8 = 1;

/// Encode a JSON payload as a single protocol line (JSON + trailing newline).
pub fn encode_json_line(payload: &Value) -> Result<Vec<u8>, String> {
    let mut line = serde_json::to_vec(payload).map_err(|err| err.to_string())?;
    line.push(b'\n');
    Ok(line)
}

/// Companion -> board handshake.
pub fn hello_payload() -> Value {
    serde_json::json!({
        "v": PROTOCOL_VERSION,
        "type": "hello",
        "payload": { "client": "companion", "version": env!("CARGO_PKG_VERSION") }
    })
}

/// Companion -> board keepalive.
pub fn ping_payload() -> Value {
    serde_json::json!({ "v": PROTOCOL_VERSION, "type": "ping" })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encode_appends_newline() {
        let line = encode_json_line(&serde_json::json!({"a": 1})).unwrap();
        assert_eq!(*line.last().unwrap(), b'\n');
        assert!(line.starts_with(b"{"));
    }

    #[test]
    fn hello_has_version_and_type() {
        let hello = hello_payload();
        assert_eq!(hello["v"], PROTOCOL_VERSION);
        assert_eq!(hello["type"], "hello");
    }

    #[test]
    fn ping_is_versioned() {
        let ping = ping_payload();
        assert_eq!(ping["v"], PROTOCOL_VERSION);
        assert_eq!(ping["type"], "ping");
    }
}
