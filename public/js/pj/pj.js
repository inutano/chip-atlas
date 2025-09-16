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
  // Debug function to log navbar state
  function debugNavbar() {
    if (window.location.search.includes("debug=navbar")) {
      console.log("Navbar Debug Info:");
      console.log("Window width:", $(window).width());
      console.log("Breakpoint: < 1346px for hamburger menu");
      console.log("Should show hamburger:", $(window).width() < 1346);
      console.log("Hamburger visible:", $(".navbar-toggle").is(":visible"));
      console.log("Collapse state:", $(".navbar-collapse").hasClass("in"));
    }
  }

  // Simple hamburger toggle - CSS handles the hiding/showing
  $(".navbar-toggle").on("click", function (e) {
    e.preventDefault();
    var $target = $("#navbar");
    var $button = $(this);

    if ($target.hasClass("in")) {
      // Close menu
      $target.removeClass("in");
      $button.addClass("collapsed").attr("aria-expanded", "false");
    } else {
      // Open menu
      $target.addClass("in");
      $button.removeClass("collapsed").attr("aria-expanded", "true");
    }
    debugNavbar();
  });

  // Close navbar when clicking on menu items
  $(".navbar-nav li a").on("click", function () {
    if ($(window).width() < 1346) {
      $("#navbar").removeClass("in");
      $(".navbar-toggle").addClass("collapsed").attr("aria-expanded", "false");
    }
  });

  // Handle form submission in navbar
  $(".navbar-form").on("submit", function (e) {
    e.preventDefault();
    var expid = $("#jumpToExperiment").val();
    if (expid.trim()) {
      window.open("/view?id=" + expid);
    }
    // Close navbar after search
    if ($(window).width() < 1346) {
      $("#navbar").removeClass("in");
      $(".navbar-toggle").addClass("collapsed").attr("aria-expanded", "false");
    }
  });

  // Reset navbar state on window resize
  $(window).resize(function () {
    if ($(window).width() >= 1346) {
      $("#navbar").removeClass("in");
      $(".navbar-toggle").addClass("collapsed").attr("aria-expanded", "false");
    }
    debugNavbar();
  });

  // Initial debug
  debugNavbar();
}
