window.onload = async () => {
  // default value for dataset
  putDefaultTitles();
  submitDMR();
}

// UI Building

const putDefaultTitles = () => {
  const defaultTitles = {
    'ProjectTitle': "My project",
    'DataSetATitle': "dataset A",
    'DataSetBTitle': "dataset B",
  };
  const genome = genomeSelected();
  for (const [id, dvalue] of Object.entries(defaultTitles)) {
    const elm = document.getElementById(genome + id);
    elm.value = dvalue;
  }
}

// Diff Analysis post functions
const submitDMR = async () => {
  const genome = genomeSelected();
  // diable when blackout
  const endpointStatusUrl = "/wabi_endpoint_status"
  let endpointStatusResponse = await fetch(endpointStatusUrl);
  let endpointStatus = await endpointStatusResponse.text();
  if (endpointStatus == 'chipatlas') {
    $("button#dmr-submit").click(function() {
      $(this).attr("disabled", true); // disable submit button
      const data = retrievePostData(genome);
      const response = postDMR(data, genome);
      $(this).attr("disabled", false); // enable submit button
      openResultPage(response, genome, data);
    });
  } else {
    $("button#dmr-submit").prop("disabled", true);
    alert("DMR analysis is currently unavailable due to the background server issue. See maintainance schedule on top page.");
  }
}

const retrievePostData = (genome) => {
  var data = {
    // address: '',
    // qsubOptions: '-N test',
    antigenClass: 'dmr',
    title: $('input#' + genome + 'ProjectTitle').val(),
    genome: genome,
    typeA: 'srx',
    bedAFile: $('textarea#' + genome + 'DataSetA').val(),
    descriptionA: $('input#' + genome + 'DataSetATitle').val(),
    typeB: 'srx',
    bedBFile: $('textarea#' + genome + 'DataSetB').val(),
    descriptionB: $('input#' + genome + 'DataSetBTitle').val(),
    format: 'text',
    result: 'www',
    cellClass: 'empty',
    threshold: 1,
    permTime: 1,
  };
  console.log(data);
  return data;
}

const postDMR = async (data, genome) => {
  const endpointUrl = '/wabi_chipatlas';
  try {
    $.ajax({
      type: 'post',
      url: "/wabi_chipatlas",
      data: JSON.stringify(data),
      contentType: 'application/json',
      dataType: 'json',
      scriptCharset: 'utf-8',
      success: function(response) {
        const requestId = response.requestId;
        const calcm = $('a#' + genome + '-estimated-run-time').text().replace(/-/g, "");
        const redirectUrl = '/enrichment_analysis_result?id=' + requestId + '&title=' + data['title'] + '&calcm=' + calcm;
        window.open(redirectUrl, "_self", "");
      },
      error: function(response) {
        console.log(data);
        console.log(response);
        alert("Something went wrong: Please let us know to fix the problem, click 'contact us' below this page." + JSON.stringify(response));
        //alert("Error: DDBJ supercomputer now unavailable: http://www.ddbj.nig.ac.jp/whatsnew");
      },
      complete: function() {
        button.attr("disabled", false);
      }
    });
  } catch (e) {
    alert(e.message);
    button.prop("disabled", false);
  }
}

const openResultPage = (response, genome, data) => {
  const requestId = response.requestId;
  const calcm = $('a#' + genome + '-estimated-run-time').text().replace(/-/g, "");
  // const redirectUrl = '/diff_analysis_result?id=' + requestId + '&title=' + data['title'] + '&calcm=' + calcm;
  const redirectUrl = '/enrichment_analysis_result?id=' + requestId + '&title=' + data['title'] + '&calcm=' + calcm;
  // window.open(redirectUrl, "_self", "");
}
