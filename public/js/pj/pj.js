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

    if (windowWidth < 768) {
      $toggle.show().removeClass("hidden");
      $collapse.addClass("collapse").removeClass("in");
    } else {
      $toggle.hide();
      $collapse.removeClass("collapse in").removeAttr("style");
    }
  }

  // Initial check and debug
  checkHamburgerVisibility();
  debugNavbar();

  // Ensure navbar collapses properly on small screens
  $(".navbar-toggle").on("click", function () {
    var target = $(this).attr("data-target");
    $(target).collapse("toggle");
    debugNavbar();
  });

  // Close navbar when clicking on menu items (on mobile)
  $(".navbar-nav li a").on("click", function () {
    if ($(window).width() < 768) {
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
    if ($(window).width() < 768) {
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
    if ($(window).width() < 768) {
      $(".navbar-collapse").collapse("hide");
    }
  });

  // Force hamburger menu to work even if Bootstrap collapse is not working
  $(".navbar-toggle").on("click", function (e) {
    e.preventDefault();
    var $target = $($(this).attr("data-target"));

    // Fallback manual toggle if Bootstrap collapse fails
    if (!$target.hasClass("collapsing")) {
      if ($target.hasClass("in") || $target.is(":visible")) {
        $target.removeClass("in").hide();
        $(this).addClass("collapsed").attr("aria-expanded", "false");
      } else {
        $target.addClass("in").show();
        $(this).removeClass("collapsed").attr("aria-expanded", "true");
      }
    }
  });
}
