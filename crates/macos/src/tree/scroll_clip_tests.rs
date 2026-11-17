use super::*;
use crate::tree::element_bounds::clipped_viewport;

const NO_SCROLL_BARS: ScrollBars = ScrollBars {
    horizontal: false,
    vertical: false,
};

const VERTICAL_SCROLL_BAR: ScrollBars = ScrollBars {
    horizontal: false,
    vertical: true,
};

fn frame(x: f64, y: f64, width: f64, height: f64) -> Rect {
    Rect {
        x,
        y,
        width,
        height,
    }
}

fn content_of(children: impl IntoIterator<Item = (Rect, bool)>) -> Option<Rect> {
    union_rects(
        children
            .into_iter()
            .filter_map(|(bounds, is_scroll_bar)| content_rect(bounds, is_scroll_bar)),
    )
}

fn offscreen(element: Rect, viewport: Option<Rect>) -> Option<bool> {
    crate::tree::state_reader::offscreen(Some(element), viewport)
}

/// Direct children of the E2E fixture's scroll area recorded on macOS 26.6,
/// as `(bounds, is_scroll_bar)`: the leftmost, rightmost and lowest content,
/// the primary button, the scroll area's own vertical scroll bar and the
/// fixture's zero-bounds button.
fn fixture_children() -> [(Rect, bool); 6] {
    [
        (frame(316.5, 82.0, 140.0, 20.5), false),
        (frame(326.5, 144.5, 113.0, 24.0), false),
        (frame(910.5, 1045.5, 220.0, 160.0), false),
        (frame(326.5, 1381.5, 145.0, 16.0), false),
        (frame(1422.0, 71.0, 19.0, 752.5), true),
        (frame(0.0, 900.0, 0.0, 0.0), false),
    ]
}

/// Geometry recorded on macOS 26.6 from the E2E fixture: the window and the
/// SwiftUI scroll area under it are 1383 points wide and the 814 points of
/// content are centred, yet the `AXScrollArea` publishes an 884-point width
/// ending at the window's right edge. The clip extends back to where the
/// content starts, so the primary button drawn at x = 326.5 is visible; the
/// content overflows vertically and the bottom edge keeps clipping.
#[test]
fn swiftui_frame_ending_at_the_viewport_edge_extends_back_to_its_content() {
    let window = Some(frame(57.0, 40.0, 1383.0, 790.0));
    let published = frame(556.0, 72.0, 884.0, 758.0);
    let clip = scroll_clip_frame(
        published,
        content_of(fixture_children()),
        VERTICAL_SCROLL_BAR,
    );
    assert_eq!(clip, frame(316.5, 72.0, 1123.5, 758.0));
    let viewport = clipped_viewport(window, "AXScrollArea", Some(clip));
    assert_eq!(viewport, Some(clip));
    assert_eq!(
        offscreen(frame(326.5, 144.5, 113.0, 24.0), viewport),
        Some(false)
    );
    assert_eq!(
        offscreen(frame(326.5, 1381.5, 145.0, 16.0), viewport),
        Some(true)
    );
}

/// The same fixture recorded on a macOS 26.7 runner with a 1004-point window:
/// the frame again ends at the window's right edge, 884 points wide, and the
/// content starts 50 points before it.
#[test]
fn swiftui_frame_on_a_narrower_window_extends_back_to_its_content() {
    let published = frame(140.0, 63.0, 884.0, 720.0);
    let content = content_of([
        (frame(90.0, 73.0, 140.0, 20.5), false),
        (frame(684.0, 1037.0, 220.0, 160.0), false),
        (frame(1006.0, 62.0, 19.0, 714.5), true),
    ]);
    assert_eq!(
        scroll_clip_frame(published, content, VERTICAL_SCROLL_BAR),
        frame(90.0, 63.0, 934.0, 720.0)
    );
}

/// A content container that fits the frame's width but passes its trailing
/// edge is clipped there, and so is its descendant lying wholly past that
/// edge, even though the window contains the descendant.
#[test]
fn content_past_the_trailing_edge_keeps_the_frame() {
    let window = Some(frame(0.0, 0.0, 1000.0, 500.0));
    let scroll_area = frame(100.0, 0.0, 100.0, 300.0);
    let container = frame(150.0, 0.0, 100.0, 300.0);
    let clip = scroll_clip_frame(scroll_area, Some(container), NO_SCROLL_BARS);
    assert_eq!(clip, scroll_area);
    let viewport = clipped_viewport(window, "AXScrollArea", Some(clip));
    assert_eq!(
        offscreen(frame(220.0, 40.0, 20.0, 20.0), viewport),
        Some(true)
    );
    assert_eq!(
        offscreen(frame(160.0, 40.0, 20.0, 20.0), viewport),
        Some(false)
    );
}

/// Content that starts before the frame extends the clip only to where the
/// content starts: a descendant drawn outside its content container, before
/// that start or past the trailing edge, stays hidden.
#[test]
fn content_before_the_leading_edge_extends_the_clip_only_to_its_start() {
    let window = Some(frame(0.0, 0.0, 1000.0, 500.0));
    let scroll_area = frame(100.0, 0.0, 100.0, 300.0);
    let container = frame(80.0, 0.0, 100.0, 300.0);
    let clip = scroll_clip_frame(scroll_area, Some(container), NO_SCROLL_BARS);
    assert_eq!(clip, frame(80.0, 0.0, 120.0, 300.0));
    let viewport = clipped_viewport(window, "AXScrollArea", Some(clip));
    assert_eq!(
        offscreen(frame(40.0, 40.0, 30.0, 20.0), viewport),
        Some(true)
    );
    assert_eq!(
        offscreen(frame(205.0, 40.0, 20.0, 20.0), viewport),
        Some(true)
    );
    assert_eq!(
        offscreen(frame(85.0, 40.0, 10.0, 20.0), viewport),
        Some(false)
    );
}

/// The scroll area's own scroll bar sits at the frame's edge and a zero-sized
/// child draws nothing; counting either as content would make the fixture's
/// content look wider than the frame and keep the wrong frame clipping.
#[test]
fn scroll_bars_and_empty_children_are_not_content() {
    assert_eq!(content_rect(frame(1422.0, 71.0, 19.0, 752.5), true), None);
    assert_eq!(content_rect(frame(0.0, 900.0, 0.0, 0.0), false), None);
    let published = frame(556.0, 72.0, 884.0, 758.0);
    let everything = union_rects(fixture_children().into_iter().map(|(bounds, _)| bounds));
    assert_eq!(
        scroll_clip_frame(published, everything, VERTICAL_SCROLL_BAR),
        published
    );
}

/// Content that overflows an axis keeps that axis clipped even without a
/// scroll bar: a SwiftUI carousel with hidden indicators, recorded on
/// macOS 26.6, scrolled so that its first item lies before the frame.
#[test]
fn overflowing_content_keeps_the_frame() {
    let carousel = frame(290.0, 333.0, 150.0, 16.0);
    let items = union_rects([
        frame(-600.0, 333.0, 67.0, 16.0),
        frame(400.0, 333.0, 66.0, 16.0),
    ]);
    assert_eq!(scroll_clip_frame(carousel, items, NO_SCROLL_BARS), carousel);
}

/// Content that fits but lies wholly outside the frame keeps the frame: an
/// AppKit scroll view without a horizontal scroller whose only exposed child
/// is a button past the right edge, and a SwiftUI scroll view on macOS 26.7
/// whose only child is published wholly before its frame (the frame error,
/// which this geometry cannot tell from content scrolled away, so it stays
/// clipped).
#[test]
fn content_wholly_outside_keeps_the_frame() {
    let appkit = frame(780.0, 191.0, 200.0, 300.0);
    let button = frame(1379.0, 446.0, 102.0, 26.0);
    let document = content_of([(button, false), (frame(962.0, 190.0, 19.0, 302.0), true)]);
    assert_eq!(
        scroll_clip_frame(appkit, document, VERTICAL_SCROLL_BAR),
        appkit
    );
    let viewport = clipped_viewport(
        Some(frame(0.0, 0.0, 1600.0, 900.0)),
        "AXScrollArea",
        Some(appkit),
    );
    assert_eq!(offscreen(button, viewport), Some(true));
    let swiftui = frame(696.0, 317.0, 64.0, 174.0);
    let text = frame(594.0, 333.0, 32.0, 16.0);
    assert_eq!(
        scroll_clip_frame(swiftui, Some(text), NO_SCROLL_BARS),
        swiftui
    );
}

/// An AppKit list inside the fixture, recorded on macOS 26.6: the outline is
/// the scroll area's only content child and reports the visible 120 points,
/// not its full height, so its rows past the bottom look like fitting content.
/// The scroll area's vertical scroll bar (an overlay, hidden while idle) shows
/// the axis scrolls, and the sixth row stays hidden behind its bottom edge.
#[test]
fn an_axis_with_a_scroll_bar_keeps_the_frame() {
    let list = frame(618.5, 568.5, 260.0, 120.0);
    let content = content_of([
        (frame(618.5, 568.5, 260.0, 120.0), false),
        (frame(860.5, 567.5, 19.0, 122.0), true),
    ]);
    assert_eq!(scroll_clip_frame(list, content, VERTICAL_SCROLL_BAR), list);
    let viewport = clipped_viewport(
        Some(frame(57.0, 72.0, 1383.0, 758.0)),
        "AXScrollArea",
        Some(list),
    );
    let row = |y| offscreen(frame(618.5, y, 260.0, 24.0), viewport);
    assert_eq!(row(674.5), Some(false));
    assert_eq!(row(698.5), Some(true));
    let scrolled = frame(618.5, 520.0, 260.0, 120.0);
    let bars = ScrollBars {
        horizontal: true,
        vertical: true,
    };
    assert_eq!(scroll_clip_frame(list, Some(scrolled), bars), list);
}

#[test]
fn unknown_content_keeps_the_frame() {
    let scroll_area = frame(0.0, 0.0, 10.0, 10.0);
    assert_eq!(
        scroll_clip_frame(scroll_area, None, NO_SCROLL_BARS),
        scroll_area
    );
    assert_eq!(union_rects(std::iter::empty()), None);
}
