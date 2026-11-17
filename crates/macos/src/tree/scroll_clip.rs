use agent_desktop_core::Rect;

use super::AXElement;

/// Most children a scroll area's content extent is measured from. A larger
/// scroll area keeps clipping along both axes.
const MAX_CONTENT_EXTENT_CHILDREN: usize = 256;

/// Content may exceed the frame by this much along an axis and still fit, for
/// fractional AppKit and SwiftUI geometry.
const CONTENT_FIT_TOLERANCE: f64 = 1.0;

/// The axes along which a clipping container hides its descendants.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct ClipAxes {
    pub(crate) horizontal: bool,
    pub(crate) vertical: bool,
}

impl ClipAxes {
    pub(crate) const BOTH: Self = Self {
        horizontal: true,
        vertical: true,
    };
}

/// The axes along which a scroll area hides content. On macOS 26 a SwiftUI
/// `AXScrollArea` publishes a frame that is not its viewport along an axis
/// whose content fits: the frame takes the content's extent at an unrelated
/// origin, so children drawn inside the window lie outside it. An axis with a
/// scroll bar scrolls, and its frame is the viewport, so it clips. Along an
/// axis without one, content that fits the frame and overlaps it cannot have
/// been scrolled out of view, so that axis does not clip and the enclosing
/// viewport still clips it; content that overflows the frame, or lies wholly
/// outside it, clips. Unknown content clips along both axes, as before.
pub(crate) fn scroll_clip_axes(
    frame: Rect,
    content: Option<Rect>,
    scroll_bars: ClipAxes,
) -> ClipAxes {
    let Some(content) = content else {
        return ClipAxes::BOTH;
    };
    ClipAxes {
        horizontal: scroll_bars.horizontal
            || !fits_along(content.x, content.width, frame.x, frame.width),
        vertical: scroll_bars.vertical
            || !fits_along(content.y, content.height, frame.y, frame.height),
    }
}

fn fits_along(start: f64, length: f64, frame_start: f64, frame_length: f64) -> bool {
    length <= frame_length + CONTENT_FIT_TOLERANCE
        && start < frame_start + frame_length
        && start + length > frame_start
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

/// The clip axes of a container whose children are already loaded. Only a
/// scroll area narrows them; an unreadable, partly bounded or oversized child
/// list keeps both axes.
pub(crate) fn clip_axes_from_children(
    container: &AXElement,
    role: &str,
    frame: Rect,
    children: &[AXElement],
    deadline: std::time::Instant,
) -> ClipAxes {
    if role != "AXScrollArea" || children.len() > MAX_CONTENT_EXTENT_CHILDREN {
        return ClipAxes::BOTH;
    }
    let mut scroll_bars = Vec::with_capacity(2);
    let mut bar_axes = ClipAxes {
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
            Err(_) => return ClipAxes::BOTH,
        }
    }
    let mut content = Vec::with_capacity(children.len());
    for child in children {
        let is_scroll_bar = scroll_bars
            .iter()
            .any(|bar| super::same_element(bar, child));
        match super::element_bounds::read_bounds_with_deadline(child, deadline) {
            Ok(Some(bounds)) => content.extend(content_rect(bounds, is_scroll_bar)),
            _ => return ClipAxes::BOTH,
        }
    }
    scroll_clip_axes(frame, union_rects(content), bar_axes)
}

/// The clip axes of a live container, reading a scroll area's children.
pub(crate) fn clip_axes(
    container: &AXElement,
    role: &str,
    frame: Rect,
    deadline: std::time::Instant,
) -> ClipAxes {
    if role != "AXScrollArea" {
        return ClipAxes::BOTH;
    }
    match super::surface_read::elements(container, "AXChildren", deadline) {
        Ok(children) => clip_axes_from_children(container, role, frame, &children, deadline),
        Err(_) => ClipAxes::BOTH,
    }
}

/// `frame` along its clipping axes and `other`'s extent along the rest.
pub(crate) fn along_clip_axes(frame: Rect, other: Rect, axes: ClipAxes) -> Rect {
    let (x, width) = if axes.horizontal {
        (frame.x, frame.width)
    } else {
        (other.x, other.width)
    };
    let (y, height) = if axes.vertical {
        (frame.y, frame.height)
    } else {
        (other.y, other.height)
    };
    Rect {
        x,
        y,
        width,
        height,
    }
}

#[cfg(test)]
#[path = "scroll_clip_tests.rs"]
mod tests;
