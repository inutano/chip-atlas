// onload
$(function () {
  dbLinkOut();
  analysisLinkOut();
  showHelp();
  loadImages();
  hideAnalysis();
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

var helpText = {
  threshold:
    "Set the threshold for statistical significance values calculated by peak-caller MACS2 (-10*Log10[MACS2 Q-value]). If 50 is set here, peaks with Q value < 1E-05 are shown on genome browser IGV.",
  viewOnIGV:
    'IGV must be running on your computer before clicking the button.\n\nIf your browser shows "cannot open the page" error, launch IGV and allow an access via port 60151 (from the menu bar of IGV, View > Preferences... > Advanced > "enable port" and set port number 60151) to browse the data. If you have not installed IGV on your computer, visit https://www.broadinstitute.org/igv/download or google "Integrative Genomics Viewer" to download the software.',
};
