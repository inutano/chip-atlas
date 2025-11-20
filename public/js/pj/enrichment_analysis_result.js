window.onload = async () => {
  const params = getUrlParameters();
  setTableValues(params);
  setClock(params);
  checkWabiStatus(params);
  startLogMonitoring(params.reqId);
};

const setTableValues = (params) => {
  $("td#project-title").text(params.title);
  $("td#request-id").text(params.reqId);

  if (params.api === "wabi") {
    $("a#result-url").text(params.resultUrl + "&format=html");
    $("a#download-tsv").text(params.resultUrl + "&format=tsv");
  } else {
    $("a#result-url").text(params.htmlUrl);
    $("a#download-tsv").text(params.tsvUrl);
  }
};

// get url parameter
const getUrlParameters = () => {
  const reqId = parseUrlParameter("id");
  const title = parseUrlParameter("title");
  const api = parseUrlParameter("api");

  let resultUrl, htmlUrl, tsvUrl;

  if (api === "wabi") {
    const wabiUrl = "https://dtn1.ddbj.nig.ac.jp:10443/wabi/chipatlas/";
    const reqUrl = wabiUrl + reqId;
    resultUrl = reqUrl + "?info=result";
  } else {
    const baseUrl =
      "https://chip-atlas.dbcls.jp/data/enrichment-analysis/" + reqId;
    htmlUrl = baseUrl + "/" + reqId + ".result.html";
    tsvUrl = baseUrl + "/" + reqId + ".result.tsv";
  }

  return {
    reqId: reqId,
    title: title,
    api: api,
    calcm: parseUrlParameter("calcm"),
    resultUrl: resultUrl,
    htmlUrl: htmlUrl,
    tsvUrl: tsvUrl,
  };
};

const parseUrlParameter = (sParam) => {
  const sPageURL = decodeURIComponent(window.location.search.substring(1));
  const sURLVariables = sPageURL.split("&");

  for (let i = 0; i < sURLVariables.length; i++) {
    const sParameterName = sURLVariables[i].split("=");
    if (sParameterName[0] === sParam) {
      return sParameterName[1] === undefined ? true : sParameterName[1];
    }
  }
};

// submit time and clock
const setClock = (params) => {
  const now = new Date();
  setSubmitTime(now);
  setEstFinish(now, params);
  activateClock();
};

const setSubmitTime = (now) => {
  $("td#submitted-at").text(dateFormat(now) + " / UTC: " + dateFormatUTC(now));
};

// date format converter function
const dateFormat = (date) => {
  const f = date.toString().split(" ");
  return f[4] + " (" + f[1] + "-" + f[2] + "-" + f[3] + ")";
};

const dateFormatUTC = (date) => {
  const f = date.toUTCString().split(" "); // 'Fri, 22 Mar 2024 06:13:17 GMT'
  return f[4] + " (" + f[2] + "-" + f[1] + "-" + f[3] + ")";
};

const setEstFinish = (now, params) => {
  const calcm = params.calcm;
  let calcTime;
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
  const estFinish = new Date(
    now.setMinutes(now.getMinutes() + parseInt(calcTime, 10)),
  );
  $("td#estimated-finishing-time").text(
    dateFormat(estFinish) + " / UTC: " + dateFormatUTC(estFinish),
  );
};

// Clock
const activateClock = () => {
  setInterval(function () {
    const t = new Date();
    $("td#current-time").text(dateFormat(t) + " / UTC: " + dateFormatUTC(t));
  }, 1000);
};

const checkWabiStatus = (params) => {
  const tdStatus = $("td#status");
  const reqId = params.reqId;

  if (params.api === "wabi") {
    const interval = setInterval(() => {
      $.get("/wabi_chipatlas?id=" + reqId, (status) => {
        tdStatus.text(status);
        if (status === "finished") {
          clearInterval(interval);
          tdStatus.css("color", "red");
          setWabiResultLinks(params);
        } else if (status === "unavailable") {
          clearInterval(interval);
          alert(
            "No response from the DDBJ supercomputer system: please note the result URL to access later. It is possible that your job has been interrupted by the system error, in that case you may need to run the analysis again.",
          );
        }
      });
    }, 10000);
  } else {
    const interval = setInterval(() => {
      $.get(
        "https://" + params.api + "/runs/" + reqId + "/status",
        (status) => {
          const state = status.state;
          tdStatus.text(state);
          if (state === "COMPLETE") {
            clearInterval(interval);
            tdStatus.css("color", "red");
            setApiResultLinks(params);
          } else if (state === "EXECUTOR_ERROR") {
            clearInterval(interval);
            alert(
              "The analysis has failed. Please try again. If the problem persists, please contact us.",
            );
          }
        },
      );
    }, 10000);
  }
};

const setWabiResultLinks = (params) => {
  $("a#result-url").attr("href", params.resultUrl + "&format=html");
  $("a#download-tsv").attr("href", params.resultUrl + "&format=tsv");
};

const setApiResultLinks = (params) => {
  $("a#result-url").attr("href", params.htmlUrl);
  $("a#download-tsv").attr("href", params.tsvUrl);
};

// Log display functions
const startLogMonitoring = (reqId) => {
  // Show log immediately and update every 10 seconds
  updateExecutionLog(reqId);
  setInterval(() => {
    updateExecutionLog(reqId);
  }, 10000);
};

const updateExecutionLog = (reqId) => {
  $.get("/enrichment_analysis_log?id=" + reqId, (logContent) => {
    pasteExecutionLog(logContent);
  }).fail((xhr) => {
    // If log is not available yet, show a message
    if (xhr.status === 404) {
      if ($(".container#executionLog").is(":empty")) {
        $(".container#executionLog").html(
          "<h3>Execution Log</h3><p>Log file not available yet. Please wait...</p>",
        );
      }
    } else {
      // Handle other errors
      if ($(".container#executionLog").is(":empty")) {
        $(".container#executionLog").html(
          "<h3>Execution Log</h3><p>Fetching log file… The page will refresh automatically.</p>",
        );
      }
    }
  });
};

const pasteExecutionLog = (logText) => {
  if (logText && logText.trim()) {
    $(".container#executionLog").html(
      "<h3>Execution Log</h3><pre><code>" + logText + "</code></pre>",
    );
  }
};
