// onload
$(function () {
  dbLinkOut();
  analysisLinkOut();
  showHelp();
  loadImages();
  hideAnalysis();
  handleStatisticsImages();
});

// variables
var dbNamespace = {
  wikigenes: "https://www.wikigenes.org/?search=",
  posmed:
    "http://omicspace.riken.jp/PosMed/search?actionType=searchexec&keyword=",
  pdbj: "http://pdbj.org/mine/search?query=",
  atcc: "http://www.atcc.org/Search_Results.aspx?searchTerms=",
  mesh: "https://www.ncbi.nlm.nih.gov/mesh/?term=",
  rikenbrc: "http://www2.brc.riken.jp/lab/cell/list.cgi?skey=",
};

var getUrlParameter = function getUrlParameter(sParam) {
  var sPageURL = decodeURIComponent(window.location.search.substring(1)),
    sURLVariables = sPageURL.split("&"),
    sParameterName,
    i;

  for (i = 0; i < sURLVariables.length; i++) {
    sParameterName = sURLVariables[i].split("=");
    if (sParameterName[0] === sParam) {
      return sParameterName[1] === undefined ? true : sParameterName[1];
    }
  }
};

// functions
function dbLinkOut() {
  $("button").on("click", function (event) {
    event.preventDefault();
    var namespace = dbNamespace[$(this).attr("id")];
    switch (true) {
      case $(this).hasClass("antigen"):
        var id = $("input#queryAntigen").val().replace(/\s/, "+");
        var uri = namespace + id;
        break;
      case $(this).hasClass("celltype"):
        var id = $("input#queryCelltype").val().replace(/\s/, "+");
        var uri = namespace + id;
        break;
    }
    window.open(uri);
  });
}

function analysisLinkOut() {
  var expid = getUrlParameter("id");
  $.ajax({
    type: "GET",
    url: "/data/exp_metadata.json?expid=" + expid,
    dataType: "json",
  }).done(function (records) {
    $.each(records, function (i, record) {
      var genome = record["genome"];
      var dbarc = "https://chip-atlas.dbcls.jp/data/" + genome;
      var urlList = [
        ["Colocalization", dbarc + "/colo/" + expid + ".html"],
        ["Target Genes (TSS ± 1kb)", dbarc + "/target/" + expid + ".1.html"],
        ["Target Genes (TSS ± 5kb)", dbarc + "/target/" + expid + ".5.html"],
        ["Target Genes (TSS ± 10kb)", dbarc + "/target/" + expid + ".10.html"],
      ];

      $.each(urlList, function (i, kv) {
        var text = kv[0];
        var url = kv[1];
        $.ajax({
          type: "GET",
          url: "/api/remoteUrlStatus?url=" + url,
          complete: function (transport) {
            if (transport.status == 200) {
              $("ul#analysisLinkOut." + genome).append(
                "<li><a href='" + url + "'>" + text + "</a></li>",
              );
            }
            if (i == urlList.length - 1) {
              if ($("ul#analysisLinkOut." + genome).children().length == 0) {
                $("ul#analysisLinkOut." + genome).append(
                  "<li class='dropdown-header'>No data available for this record</li>",
                );
              }
            }
          },
        });
      });
    });
  });
}

function showHelp() {
  $(".infoBtn").click(function () {
    switch ($(this).attr("id")) {
      case "viewOnIGV":
        alert(helpText["viewOnIGV"]);
        break;
    }
  });
}

function hideAnalysis() {
  var analysisButton = $("div#analyze-dropdown");
  var expType = analysisButton.attr("experiment");
  if (expType == "Bisulfite-Seq") {
    analysisButton.hide();
  }
}

function loadImages() {
  // Placeholder for image loading functionality
  // This function was being called but not defined
}

function handleStatisticsImages() {
  var $statisticsPanel = $("#statistics-panel");
  var hasAvailableData = false;
  var sectionsToCheck = $(".statistics-section").length;
  var sectionsChecked = 0;

  // Check each statistics section
  $(".statistics-section").each(function () {
    var $section = $(this);
    var distributionUrl = $section.data("distribution-url");
    var correlationUrl = $section.data("correlation-url");
    var $distributionImg = $section.find(".distribution-img");
    var $correlationImg = $section.find(".correlation-img");
    var $distributionContainer = $section.find(".distribution-container");
    var $correlationContainer = $section.find(".correlation-container");
    var $downloadContainer = $section.find(".download-container");
    var $infoSection = $section.find(".info-section");

    var sectionHasData = false;

    // Check distribution image
    var distributionPromise = new Promise(function (resolve) {
      var testImg = new Image();
      testImg.onload = function () {
        $distributionContainer.find(".loading-indicator").hide();
        $distributionImg.show();
        sectionHasData = true;
        resolve(true);
      };
      testImg.onerror = function () {
        $distributionContainer.find(".loading-indicator").hide();
        resolve(false);
      };
      testImg.src = distributionUrl;
    });

    // Check correlation image
    var correlationPromise = new Promise(function (resolve) {
      var testImg = new Image();
      testImg.onload = function () {
        $correlationContainer.find(".loading-indicator").hide();
        $correlationImg.show();
        $downloadContainer.show();
        sectionHasData = true;
        resolve(true);
      };
      testImg.onerror = function () {
        $correlationContainer.find(".loading-indicator").hide();
        resolve(false);
      };
      testImg.src = correlationUrl;
    });

    // Wait for both images to be checked
    Promise.all([distributionPromise, correlationPromise]).then(function () {
      sectionsChecked++;

      if (sectionHasData) {
        hasAvailableData = true;
        $infoSection.show();
        // Show the entire section including the genome header
        $section.show();
      } else {
        // Hide the entire section if no data is available
        $section.hide();
      }

      // If all sections have been checked, show/hide panel accordingly
      if (sectionsChecked === sectionsToCheck) {
        if (hasAvailableData) {
          $statisticsPanel.show();
          setupImageInteractions();
          setupSeparators();
        }
        // If no data available, panel remains hidden
      }
    });
  });
}

function setupImageInteractions() {
  // Add click handlers for image zoom functionality
  $(".distribution-img, .correlation-img").on("click", function () {
    var $img = $(this);
    var imgSrc = $img.attr("src");
    var imgAlt = $img.attr("alt");

    // Create modal for zoomed view
    var modalHtml =
      '<div class="modal fade" id="imageModal" tabindex="-1" role="dialog">' +
      '<div class="modal-dialog modal-lg" role="document">' +
      '<div class="modal-content">' +
      '<div class="modal-header">' +
      '<button type="button" class="close" data-dismiss="modal" aria-label="Close">' +
      '<span aria-hidden="true">&times;</span>' +
      "</button>" +
      '<h4 class="modal-title">' +
      imgAlt +
      "</h4>" +
      "</div>" +
      '<div class="modal-body text-center">' +
      '<img src="' +
      imgSrc +
      '" class="img-responsive" alt="' +
      imgAlt +
      '" style="max-width: 100%; height: auto;">' +
      "</div>" +
      '<div class="modal-footer">' +
      '<button type="button" class="btn btn-default" data-dismiss="modal">Close</button>' +
      "</div>" +
      "</div>" +
      "</div>" +
      "</div>";

    // Remove existing modal if any
    $("#imageModal").remove();

    // Add modal to body and show
    $("body").append(modalHtml);
    $("#imageModal").modal("show");
  });

  // Add cursor pointer style for clickable images
  $(".distribution-img, .correlation-img").css("cursor", "pointer");

  // Add tooltip for download button
  $('a[download*="correlation"]').attr(
    "title",
    "Download detailed correlation data in TSV format",
  );
}

function setupSeparators() {
  // Show separators between visible genome sections
  var $visibleSections = $(".statistics-section:visible");

  if ($visibleSections.length > 1) {
    // Show separators for all visible sections except the last one
    $visibleSections.each(function (index) {
      if (index < $visibleSections.length - 1) {
        $(this).find(".genome-separator").show();
      }
    });
  }
}

var helpText = {
  threshold:
    "Set the threshold for statistical significance values calculated by peak-caller MACS2 (-10*Log10[MACS2 Q-value]). If 50 is set here, peaks with Q value < 1E-05 are shown on genome browser IGV.",
  viewOnIGV:
    'IGV must be running on your computer before clicking the button.\n\nIf your browser shows "cannot open the page" error, launch IGV and allow an access via port 60151 (from the menu bar of IGV, View > Preferences... > Advanced > "enable port" and set port number 60151) to browse the data. If you have not installed IGV on your computer, visit https://www.broadinstitute.org/igv/download or google "Integrative Genomics Viewer" to download the software.',
};
