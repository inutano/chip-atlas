// get url parameter
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

// set variables
var reqId = getUrlParameter("id");
var title = getUrlParameter("title");

$("td#project-title").text(title);
$("td#request-id").text(reqId);

var api = getUrlParameter("api");

// Change resultUrl by the API
if (api == "wabi") {
  var wabiUrl = "https://ddbj.nig.ac.jp/wabi/chipatlas/";
  var reqUrl = wabiUrl + reqId;
  var resultUrl = reqUrl + "?info=result";
  $("a#result-url").text(resultUrl + "&format=html");
  $("a#download-tsv").text(resultUrl + "&format=tsv");

  // checking status
  $(function () {
    var tdStatus = $("td#status");
    var interval = setInterval(function () {
      $.get("/wabi_chipatlas?id=" + reqId, function (status) {
        tdStatus.text(status);
        if (status == "finished") {
          tdStatus.css("color", "red");
          $("a#result-url").attr("href", resultUrl + "&format=html");
          $("a#download-tsv").attr("href", resultUrl + "&format=tsv");
          clearInterval(interval);
        } else if (status == "unavailable") {
          alert(
            "No response from the DDBJ supercomputer system: please note the result URL to access later. It is possible that your job has been interrupted by the system error, in that case you may need to run the analysis again.",
          );
          clearInterval(interval);
        }
      });
    }, 10000);
  });
} else {
  var resultUrl =
    "https://chip-atlas.dbcls.jp/data/enrichment-analysis" + reqId;
  $("a#result-url").text(resultUrl + reqId + ".result.html");
  $("a#download-tsv").text(resultUrl + reqId + ".result.tsv");

  // check if the run state is complete
  // state api will return json object with key "state" and value like "RUNNING", "COMPLETE", "EXECUTOR_ERROR", etc.
  $(function () {
    var tdStatus = $("td#status");
    var interval = setInterval(function () {
      $.get("http://" + api + "/runs/" + reqId + "/status", function (status) {
        var state = JSON.parse(status).state;
        tdStatus.text(state);
        if (state == "COMPLETE") {
          tdStatus.css("color", "red");
          $("a#result-url").attr("href", resultUrl + reqId + ".result.html");
          $("a#download-tsv").attr("href", resultUrl + reqId + ".result.tsv");
          clearInterval(interval);
        } else if (status == "EXECUTOR_ERROR") {
          alert(
            "The analysis has failed. Please try again. If the problem persists, please contact us.",
          );
          clearInterval(interval);
        }
      });
    }, 10000);
  });
}

// date format converter function
function dateFormat(date) {
  var f = date.toString().split(" ");
  return f[4] + " (" + f[1] + "-" + f[2] + "-" + f[3] + ")";
}

function dateFormatUTC(date) {
  var f = date.toUTCString().split(" "); // 'Fri, 22 Mar 2024 06:13:17 GMT'
  return f[4] + " (" + f[2] + "-" + f[1] + "-" + f[3] + ")";
}

// submit time and clock
var now = new Date();
$("td#submitted-at").text(dateFormat(now) + " / UTC: " + dateFormatUTC(now));

var calcm = getUrlParameter("calcm");
var calcTime;
switch (true) {
  case "-" == calcm:
    calcTime = 0;
    break;
  case /mins$/.test(calcm):
    calcTime = calcm.split(" ")[0];
    break;
  case /hr$/.test(calcm):
    calcTime = calcm.split(" ")[0] * 60;
    break;
}
var estFinish = new Date(
  now.setMinutes(now.getMinutes() + parseInt(calcTime, 10)),
);
$("td#estimated-finishing-time").text(
  dateFormat(estFinish) + " / UTC: " + dateFormatUTC(estFinish),
);

// Clock
$(function () {
  setInterval(function () {
    t = new Date();
    $("td#current-time").text(dateFormat(t) + " / UTC: " + dateFormatUTC(t));
  }, 1000);
});
