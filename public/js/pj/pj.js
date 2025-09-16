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
      console.log(
        "Navbar collapsed:",
        $(".navbar-collapse").hasClass("collapse"),
      );
      console.log("Bootstrap loaded:", typeof $.fn.collapse !== "undefined");
    }
  }

  // Ensure hamburger button is always visible when needed
  function checkHamburgerVisibility() {
    var windowWidth = $(window).width();
    var $toggle = $(".navbar-toggle");
    var $collapse = $(".navbar-collapse");
    var $nav = $(".navbar-nav");

    if (windowWidth < 1346) {
      $toggle.show().removeClass("hidden");
      $collapse
        .addClass("collapse")
        .removeClass("in")
        .attr("aria-expanded", "false");
      $toggle.addClass("collapsed").attr("aria-expanded", "false");
      // Hide regular nav items, they'll show in collapsed menu
      $nav.hide();
    } else {
      $toggle.hide();
      $collapse.removeClass("collapse in").removeAttr("style");
      // Show regular nav items
      $nav.show();
    }
  }

  // Initial check and debug
  checkHamburgerVisibility();
  debugNavbar();

  // Ensure navbar collapses properly on small screens
  $(".navbar-toggle").on("click", function () {
    var target = $(this).attr("data-target");
    var $target = $(target);
    var $nav = $target.find(".navbar-nav");

    if ($target.hasClass("in")) {
      $target.removeClass("in").attr("aria-expanded", "false");
      $(this).addClass("collapsed").attr("aria-expanded", "false");
      $nav.hide();
    } else {
      $target.addClass("in").attr("aria-expanded", "true");
      $(this).removeClass("collapsed").attr("aria-expanded", "true");
      $nav.show();
    }
    debugNavbar();
  });

  // Close navbar when clicking on menu items (on mobile)
  $(".navbar-nav li a").on("click", function () {
    if ($(window).width() < 1346) {
      $(".navbar-collapse").collapse("hide");
    }
  });

  // Handle window resize to ensure proper navbar behavior
  $(window).resize(function () {
    checkHamburgerVisibility();
    debugNavbar();
  });

  // Improve search form behavior on mobile
  $("#jumpToExperiment").on("focus", function () {
    if ($(window).width() < 1346) {
      // Scroll to top to ensure search field is visible
      $("html, body").animate({ scrollTop: 0 }, 300);
    }
  });

  // Handle form submission in navbar
  $(".navbar-form").on("submit", function (e) {
    e.preventDefault();
    var expid = $("#jumpToExperiment").val();
    if (expid.trim()) {
      window.open("/view?id=" + expid);
    }
    // Close navbar on mobile after search
    if ($(window).width() < 1346) {
      $(".navbar-collapse").collapse("hide");
    }
  });

  // Additional click handler to ensure proper toggling
  $(".navbar-toggle").on("click", function (e) {
    // Let the first click handler run first, then this one
    var self = this;
    setTimeout(function () {
      var $target = $($(self).attr("data-target"));
      var $nav = $target.find(".navbar-nav");

      // Ensure nav visibility matches collapse state
      if ($target.hasClass("in")) {
        $nav.show();
      } else {
        $nav.hide();
      }
    }, 50);
  });
}
