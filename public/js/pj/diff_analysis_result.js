window.onload = async () => {
  const params = getUrlParameters();
  setTableValues(params);
  setClock(params);
  checkWabiStatus(params);
}

const setTableValues = (params) => {
  // const wabiUrl = "https://ddbj.nig.ac.jp/wabi/chipatlas/";
  // const reqUrl = wabiUrl + reqId;
  // const resultUrl = reqUrl + "?info=result";

  $('td#project-title').text(params.title);
  $('td#request-id').text(params.reqId);
  $('a#view-on-igv').text(params.localIgvUrl);
  $('a#download-result').text(params.zipUrl);
}

// get url parameter
const getUrlParameters = () => {
  const reqId = parseUrlParameter('id');
  const genome = parseUrlParameter('genome');
  return {
    reqId: reqId,
    title: parseUrlParameter('title'),
    genome: genome,
    calcm: parseUrlParameter('calcm'),
    localIgvUrl: 'http://localhost:60151/load?file=https://chip-atlas.dbcls.jp/data/query/' + reqId + '.igv.bed&genome=' + genome,
    zipUrl: "https://chip-atlas.dbcls.jp/data/query/" + reqId + '.zip',
  };
}

const parseUrlParameter = (sParam) => {
  const sPageURL = decodeURIComponent(window.location.search.substring(1));
  const sURLVariables = sPageURL.split('&');

  for (i = 0; i < sURLVariables.length; i++) {
    sParameterName = sURLVariables[i].split('=');
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
}

const setSubmitTime = (now) => {
  $('td#submitted-at').text(dateFormat(now));
}

const dateFormat = (date) => {
  const f = date.toString().split(" ");
  return f[4] + " (" + f[1] + "-" + f[2] + "-" + f[3] + ")";
}

const setEstFinish = (now, params) => {
  const calcm = params.calcm;
  var calcTime;
  switch (true) {
    case "-" == calcm: {
      let calcTime = 0;
      break;
    }
    case /mins$/.test(calcm): {
      let calcTime = calcm.split(" ")[0];
      break;
    }
    case /hr$/.test(calcm): {
      let calcTime = calcm.split(" ")[0] * 60;
      break;
    }
  }
  const estFinish = new Date(now.setMinutes(now.getMinutes() + parseInt(calcTime, 10)));
  $('td#estimated-finishing-time').text(dateFormat(estFinish));
}

const activateClock = () => {
  setInterval(function() {
    t = new Date();
    $('td#current-time').text(dateFormat(t));
  }, 1000);
}

const checkWabiStatus = (params) => {
  const tdStatus = $('td#status');
  const reqId = params['reqId'];
  const interval = setInterval(() => {
    $.get("/wabi_chipatlas?id=" + reqId, (status) => {
      tdStatus.text(status);
      if (status == "finished") {
        tdStatus.css("color", "red");
        setResultALink(params);
        clearInterval(interval);
      } else if (status == "unavailable") {
        alert("No response from the DDBJ supercomputer system: please note the result URL to access later. It is possible that your job has been interrupted by the system error, in that case you may need to run the analysis again.");
        clearInterval(interval);
      }
    });
  }, 10000);
}

const setResultALink = (params) => {
  $('a#view-on-igv').attr('href', params.localIgvUrl);
  $('a#download-result').attr('href', params.zipUrl);
}
