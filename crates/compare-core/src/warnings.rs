use crate::Error;
use std::io::{self, Write};

pub const MAX_COUNT: usize = 100000;
pub const MAX_BYTES: usize = 20 * 1024 * 1024;
pub const PAGE_SIZE: usize = 200;

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SourceWarning {
    pub code: &'static str,
    pub message: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub side: Option<&'static str>,
    pub line: usize,
    pub column: usize,
    pub previous_line: usize,
    pub previous_column: usize,
}

fn limit_error() -> Error {
    Error::new(
        "RESOURCE_LIMIT",
        "源码警告超过 100000 项或 20 MiB，请缩小输入。",
    )
}

// Count the exact UTF-8 JSON bytes without allocating another encoded array.
struct SizeWriter {
    bytes: usize,
    limit: usize,
}
impl Write for SizeWriter {
    fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
        let next = self
            .bytes
            .checked_add(buffer.len())
            .filter(|size| *size <= self.limit)
            .ok_or_else(|| io::Error::other("warning byte budget"))?;
        self.bytes = next;
        Ok(buffer.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

pub struct Budget {
    count: usize,
    bytes: usize,
    max_count: usize,
    max_bytes: usize,
}
impl Default for Budget {
    fn default() -> Self {
        Self {
            count: 0,
            bytes: 2,
            max_count: MAX_COUNT,
            max_bytes: MAX_BYTES,
        }
    }
}
impl Budget {
    pub fn add(&mut self, warning: &SourceWarning) -> Result<(), Error> {
        if self.count >= self.max_count {
            return Err(limit_error());
        }
        let mut writer = SizeWriter {
            bytes: self.bytes + usize::from(self.count > 0),
            limit: self.max_bytes,
        };
        serde_json::to_writer(&mut writer, warning).map_err(|_| limit_error())?;
        self.count += 1;
        self.bytes = writer.bytes;
        Ok(())
    }
}
pub fn validate(warnings: &[SourceWarning]) -> Result<(), Error> {
    if warnings.len() > MAX_COUNT {
        return Err(limit_error());
    }
    let mut budget = Budget::default();
    for warning in warnings {
        budget.add(warning)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn byte_budget_counts_utf8_array_punctuation_and_side_metadata_exactly() {
        let warning = SourceWarning {
            code: "JS_DUPLICATE_PROPERTY",
            message: "中文说明",
            side: Some("A"),
            line: 3,
            column: 10,
            previous_line: 2,
            previous_column: 3,
        };
        let exact = serde_json::to_vec(&[&warning, &warning]).unwrap().len();
        let mut budget = Budget {
            max_bytes: exact,
            ..Budget::default()
        };
        budget.add(&warning).unwrap();
        budget.add(&warning).unwrap();
        assert_eq!(budget.bytes, exact);
        let mut too_small = Budget {
            max_bytes: exact - 1,
            ..Budget::default()
        };
        too_small.add(&warning).unwrap();
        assert_eq!(too_small.add(&warning).unwrap_err().code, "RESOURCE_LIMIT");
        assert_eq!(too_small.count, 1);
    }
}
