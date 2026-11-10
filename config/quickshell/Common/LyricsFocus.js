.pragma library

// Shared lockscreen, desktop and notch focus treatment. Plain lyrics select
// their focus by reader scroll, without fabricating playback timestamps.
function blur(distance) { return Math.min(0.55, 0.14 * Math.abs(distance)); }
function opacity(distance) { return distance === 0 ? 1 : Math.abs(distance) === 1 ? 0.42 : 0.26; }
function scale(distance) { return distance === 0 ? 1 : 0.965; }
function scrollDuration(relative) { return 500 + Math.max(0, Math.min(8, relative)) * 20; }
function indexAtFocus(view) {
    var index = view.indexAt(1, view.contentY + view.preferredHighlightBegin + 1);
    if (index < 0) index = view.indexAt(1, view.contentY + 8);
    return index < 0 ? Math.max(0, view.currentIndex) : index;
}
