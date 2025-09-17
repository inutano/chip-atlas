// onload
$(function () {
  // experiment search button
  enableExperimentSearch();
  setJumbotronHeight();
  initResponsiveNavbar();
});

const setJumbotronHeight = () => {
  let maxHeight = 0;
  $(".jumbotron").each(function () {
    var jumbotronHeight = $(this).height();
    maxHeight = Math.max(maxHeight, jumbotronHeight);
  });
  // 各Jumbotronに最大高さを設定
  $(".jumbotron").height(maxHeight);
};

// common functions

function enableExperimentSearch() {
  $("button.go-experiment").on("click", function (event) {
    event.preventDefault();
    var expid = $("input#jumpToExperiment").val();
    window.open("/view?id=" + expid);
  });
}

function genomeSelected() {
  return $(".genomeTab ul li.active a")
    .attr("source")
    .replace(/[\n\s ]/g, "");
}

function tabTriggerEvents() {
  $('a[data-toggle="tab"]').on("shown.bs.tab", function (e) {
    var activatedTab = e.target;
    var previousTab = e.relatedTarget;
  });
}

function tabControl(genome) {
  $("#" + genome + "-tab a").click(function (e) {
    e.preventDefault();
    $(this).tab("show");
  });
}

function initResponsiveNavbar() {
  // Handle form submission in navbar
  $(".navbar-form").on("submit", function (e) {
    e.preventDefault();
    var expid = $("#jumpToExperiment").val();
    if (expid.trim()) {
      window.open("/view?id=" + expid);
    }
  });
}
