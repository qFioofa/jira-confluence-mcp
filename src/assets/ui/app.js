(function () {
  "use strict";

  function css(name, fallback) {
    var value = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    return value || fallback;
  }

  function renderActivity() {
    var el = document.getElementById("activity-chart");
    if (!el || typeof uPlot === "undefined") return;
    var points;
    try {
      points = JSON.parse(el.dataset.points || "[]");
    } catch (error) {
      return;
    }
    if (!points.length) return;

    var xs = points.map(function (point) {
      return new Date(point.at).getTime() / 1000;
    });
    var requests = points.map(function (point) { return point.requests || 0; });
    var hits = points.map(function (point) { return point.cache_hits || 0; });

    var accent = css("--accent", "#1b4dd8");
    var ok = css("--ok", "#1c6b4a");
    var rule = css("--rule", "#c9cec6");

    var options = {
      width: el.clientWidth,
      height: 72,
      legend: { show: false },
      cursor: { show: false },
      scales: { x: { time: true }, y: { range: function (u, min, max) { return [0, Math.max(max, 1)]; } } },
      axes: [
        { show: false },
        { show: false, stroke: rule }
      ],
      series: [
        {},
        { label: "requests", stroke: accent, width: 1.5, fill: accent + "22" },
        { label: "cache hits", stroke: ok, width: 1, dash: [3, 3] }
      ]
    };

    if (el._uplot) {
      el._uplot.destroy();
      el.innerHTML = "";
    }
    el._uplot = new uPlot(options, [xs, requests, hits], el);
  }

  function boot() {
    renderActivity();
    var resize;
    window.addEventListener("resize", function () {
      clearTimeout(resize);
      resize = setTimeout(renderActivity, 150);
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
