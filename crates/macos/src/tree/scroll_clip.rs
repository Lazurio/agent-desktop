use agent_desktop_core::Rect;

use super::AXElement;

/// Most children a scroll area's content extent is measured from. A larger
/// scroll area clips by its frame.
const MAX_CONTENT_EXTENT_CHILDREN: usize = 256;

/// Content may exceed the frame by this much along an axis and still fit, for
/// fractional AppKit and SwiftUI geometry.
const CONTENT_FIT_TOLERANCE: f64 = 1.0;

/// The axes along which a scroll area exposes a scroll bar.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct ScrollBars {
    pub(crate) horizontal: bool,
    pub(crate) vertical: bool,
}

/// The rectangle a scroll area clips its descendants to. On macOS 26 a
/// SwiftUI `AXScrollArea` publishes, along an axis whose content fits, a
/// frame that ends at the viewport's trailing edge but starts after its
/// leading edge, so content drawn near the leading edge lies before the
/// frame. An axis with a scroll bar scrolls, and its frame is the viewport.
/// Along an axis without one, content that fits the frame, overlaps it and
/// stays before its trailing edge extends the clip back to where that content
/// starts; the trailing edge, and every other case, clips by the frame.
/// Unknown content clips by the frame.
pub(crate) fn scroll_clip_frame(
    frame: Rect,
    content: Option<Rect>,
    scroll_bars: ScrollBars,
) -> Rect {
    let Some(content) = content else {
        return frame;
    };
    let (x, width) = clip_along(
        (frame.x, frame.width),
        (content.x, content.width),
        scroll_bars.horizontal,
    );
    let (y, height) = clip_along(
        (frame.y, frame.height),
        (content.y, content.height),
        scroll_bars.vertical,
    );
    Rect {
        x,
        y,
        width,
        height,
    }
}

fn clip_along(frame: (f64, f64), content: (f64, f64), scroll_bar: bool) -> (f64, f64) {
    let (frame_start, frame_length) = frame;
    let (content_start, content_length) = content;
    let frame_end = frame_start + frame_length;
    let content_end = content_start + content_length;
    let leads_into_frame = content_length <= frame_length + CONTENT_FIT_TOLERANCE
        && content_end <= frame_end + CONTENT_FIT_TOLERANCE
        && content_end > frame_start;
    if scroll_bar || !leads_into_frame || content_start >= frame_start {
        return frame;
    }
    (content_start, frame_end - content_start)
}

/// The smallest rectangle that holds every rectangle, `None` for none.
pub(crate) fn union_rects(rects: impl IntoIterator<Item = Rect>) -> Option<Rect> {
    rects.into_iter().reduce(|left, right| {
        let x = left.x.min(right.x);
        let y = left.y.min(right.y);
        Rect {
            x,
            y,
            width: (left.x + left.width).max(right.x + right.width) - x,
            height: (left.y + left.height).max(right.y + right.height) - y,
        }
    })
}

/// The part of a scroll area that a child occupies as content: its bounds,
/// unless it is one of the scroll area's own scroll bars, which sit at the
/// frame's edge and are not content, or it draws nothing (a zero-sized
/// element is never visible and does not show where content ends).
pub(crate) fn content_rect(bounds: Rect, is_scroll_bar: bool) -> Option<Rect> {
    (!is_scroll_bar && bounds.width > 0.0 && bounds.height > 0.0).then_some(bounds)
}

/// The clip rectangle of a container whose children are already loaded. Only
/// a scroll area may differ from its frame; an unreadable, partly bounded or
/// oversized child list keeps the frame.
pub(crate) fn clip_frame_from_children(
    container: &AXElement,
    role: &str,
    frame: Rect,
    children: &[AXElement],
    deadline: std::time::Instant,
) -> Rect {
    if role != "AXScrollArea" || children.len() > MAX_CONTENT_EXTENT_CHILDREN {
        return frame;
    }
    let mut scroll_bars = Vec::with_capacity(2);
    let mut bar_axes = ScrollBars {
        horizontal: false,
        vertical: false,
    };
    for (attribute, vertical) in [
        ("AXVerticalScrollBar", true),
        ("AXHorizontalScrollBar", false),
    ] {
        match super::surface_read::element(container, attribute, deadline) {
            Ok(Some(bar)) => {
                scroll_bars.push(bar);
                if vertical {
                    bar_axes.vertical = true;
                } else {
                    bar_axes.horizontal = true;
                }
            }
            Ok(None) => {}
            Err(_) => return frame,
        }
    }
    let mut content = Vec::with_capacity(children.len());
    for child in children {
        let is_scroll_bar = scroll_bars
            .iter()
            .any(|bar| super::same_element(bar, child));
        match super::element_bounds::read_bounds_with_deadline(child, deadline) {
            Ok(Some(bounds)) => content.extend(content_rect(bounds, is_scroll_bar)),
            _ => return frame,
        }
    }
    scroll_clip_frame(frame, union_rects(content), bar_axes)
}

/// The clip rectangle of a live container, reading a scroll area's children.
pub(crate) fn clip_frame(
    container: &AXElement,
    role: &str,
    frame: Rect,
    deadline: std::time::Instant,
) -> Rect {
    if role != "AXScrollArea" {
        return frame;
    }
    match super::surface_read::elements(container, "AXChildren", deadline) {
        Ok(children) => clip_frame_from_children(container, role, frame, &children, deadline),
        Err(_) => frame,
    }
}

#[cfg(test)]
#[path = "scroll_clip_tests.rs"]
mod tests;
