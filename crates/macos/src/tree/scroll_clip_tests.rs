use super::*;
use crate::tree::element_bounds::clipped_viewport;

const NO_SCROLL_BARS: ClipAxes = ClipAxes {
    horizontal: false,
    vertical: false,
};

const VERTICAL_SCROLL_BAR: ClipAxes = ClipAxes {
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
/// at the window's right edge. The primary button is drawn at x = 326.5,
/// fully inside the window, and must not be reported offscreen; the
/// content still overflows vertically, so the bottom edge keeps clipping.
#[test]
fn swiftui_scroll_area_frame_does_not_hide_content_that_fits() {
    let window = Some(frame(57.0, 40.0, 1383.0, 790.0));
    let published = frame(556.0, 72.0, 884.0, 758.0);
    let content = union_rects(
        fixture_children()
            .into_iter()
            .filter_map(|(bounds, is_scroll_bar)| content_rect(bounds, is_scroll_bar)),
    );
    let axes = scroll_clip_axes(published, content, VERTICAL_SCROLL_BAR);
    assert_eq!(
        axes,
        ClipAxes {
            horizontal: false,
            vertical: true
        }
    );
    let viewport = clipped_viewport(window, "AXScrollArea", Some(published), axes);
    assert_eq!(viewport, Some(frame(57.0, 72.0, 1383.0, 758.0)));
    let offscreen = |rect| crate::tree::state_reader::offscreen(Some(rect), viewport);
    assert_eq!(offscreen(frame(326.5, 144.5, 113.0, 24.0)), Some(false));
    assert_eq!(offscreen(frame(326.5, 1381.5, 145.0, 16.0)), Some(true));
}

/// The scroll area's own scroll bar sits at the frame's edge and a zero-sized
/// child draws nothing; counting either as content would make the fixture's
/// content look wider than the frame and keep the wrong frame clipping.
#[test]
fn scroll_bars_and_empty_children_are_not_content() {
    assert_eq!(content_rect(frame(1422.0, 71.0, 19.0, 752.5), true), None);
    assert_eq!(content_rect(frame(0.0, 900.0, 0.0, 0.0), false), None);
    let everything = union_rects(fixture_children().into_iter().map(|(bounds, _)| bounds));
    assert!(
        scroll_clip_axes(frame(556.0, 72.0, 884.0, 758.0), everything, NO_SCROLL_BARS).horizontal
    );
}

/// Content that overflows an axis keeps that axis clipped even without a
/// scroll bar: a SwiftUI carousel with hidden indicators, recorded on
/// macOS 26.6.
#[test]
fn overflowing_content_keeps_its_axis_clipped() {
    let carousel = frame(290.0, 333.0, 150.0, 16.0);
    let items = union_rects([
        frame(290.0, 333.0, 67.0, 16.0),
        frame(1200.0, 333.0, 66.0, 16.0),
    ]);
    assert_eq!(
        scroll_clip_axes(carousel, items, NO_SCROLL_BARS),
        ClipAxes {
            horizontal: true,
            vertical: false
        }
    );
}

/// Content that fits but lies wholly outside the frame has been scrolled
/// away: an AppKit scroll view without a horizontal scroller whose only
/// exposed child is a button scrolled past the right edge, recorded on
/// macOS 26.6 (its vertical scroll bar is not content).
#[test]
fn content_scrolled_wholly_outside_keeps_its_axis_clipped() {
    let appkit = frame(780.0, 191.0, 200.0, 300.0);
    let button = frame(1379.0, 446.0, 102.0, 26.0);
    let document = union_rects(
        [(button, false), (frame(962.0, 190.0, 19.0, 302.0), true)]
            .into_iter()
            .filter_map(|(bounds, is_scroll_bar)| content_rect(bounds, is_scroll_bar)),
    );
    let axes = scroll_clip_axes(appkit, document, VERTICAL_SCROLL_BAR);
    assert!(axes.horizontal);
    let viewport = clipped_viewport(
        Some(frame(0.0, 0.0, 1600.0, 900.0)),
        "AXScrollArea",
        Some(appkit),
        axes,
    );
    assert_eq!(
        crate::tree::state_reader::offscreen(Some(button), viewport),
        Some(true)
    );
}

/// An AppKit list inside the fixture, recorded on macOS 26.6: the outline is
/// the scroll area's only content child and reports the visible 120 points,
/// not its full height, so its rows past the bottom look like fitting content.
/// The scroll area's vertical scroll bar (an overlay, hidden while idle) shows
/// the axis scrolls, and the sixth row stays hidden behind its bottom edge.
#[test]
fn an_axis_with_a_scroll_bar_clips_even_when_content_seems_to_fit() {
    let list = frame(618.5, 568.5, 260.0, 120.0);
    let content = union_rects(
        [
            (frame(618.5, 568.5, 260.0, 120.0), false),
            (frame(860.5, 567.5, 19.0, 122.0), true),
        ]
        .into_iter()
        .filter_map(|(bounds, is_scroll_bar)| content_rect(bounds, is_scroll_bar)),
    );
    let axes = scroll_clip_axes(list, content, VERTICAL_SCROLL_BAR);
    assert_eq!(axes, VERTICAL_SCROLL_BAR);
    let viewport = clipped_viewport(
        Some(frame(57.0, 72.0, 1383.0, 758.0)),
        "AXScrollArea",
        Some(list),
        axes,
    );
    let row =
        |y| crate::tree::state_reader::offscreen(Some(frame(618.5, y, 260.0, 24.0)), viewport);
    assert_eq!(row(674.5), Some(false));
    assert_eq!(row(698.5), Some(true));
}

#[test]
fn unknown_content_clips_both_axes() {
    assert_eq!(
        scroll_clip_axes(frame(0.0, 0.0, 10.0, 10.0), None, NO_SCROLL_BARS),
        ClipAxes::BOTH
    );
    assert_eq!(union_rects(std::iter::empty()), None);
}
