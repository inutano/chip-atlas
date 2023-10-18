window.onload = async () => {
  // Initialize
  putDefaultTitles();
  submitDMR();
  // Events
  putExampleData();
  emptyDataSet();
  setGenomePanel();
  estimateTimeOnEdit();
  alertHelpMessage();
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

// Change to empty textarea
const emptyDataSet = () => {
  $('input#diffOrDMR').change(function(){
    const genome = genomeSelected();
    $('textarea#' + genome + 'DataSetA').val('');
    $('textarea#' + genome + 'DataSetB').val('');
    $('a#' + genome + '-estimated-run-time').html('-');
  });
}

// Example data
const putExampleData = () => {
  $('a.dataExample').on('click', function(event) {
    event.preventDefault();
    event.stopPropagation();
    const genome = genomeSelected();
    const expType = $('input[name="' + genome + 'DiffOrDMR"]:checked').val();
    let set = $(this).attr("name");
    let example = diffExampleData[genome][expType][set].split(",").join("\n");
    switch (set) {
      case 'dataSetA':
        $('textarea#' + genome + 'DataSetA').val(example);
        break;
      case 'dataSetB':
        $('textarea#' + genome + 'DataSetB').val(example);
        break;
    }
    calculateEstimatedTime();
  });
}

const diffExampleData = {
  hg38: {
    diff: {
      dataSetA: "SRX3734456,SRX3734457,SRX3734458",
      dataSetB: "SRX3734459,SRX3734460,SRX3734461"
    },
    DMR: {
      dataSetA: "SRX10768416,SRX10768417,SRX10768418,SRX10768419,SRX10768420",
      dataSetB: "SRX10768322,SRX10768323,SRX10768324,SRX10768325,SRX10768326"
    }
  },
  hg19: {
    diff: {
      dataSetA: "SRX3734456,SRX3734457,SRX3734458",
      dataSetB: "SRX3734459,SRX3734460,SRX3734461"
    },
    DMR: {
      dataSetA: "SRX10768416,SRX10768417,SRX10768418,SRX10768419,SRX10768420",
      dataSetB: "SRX10768322,SRX10768323,SRX10768324,SRX10768325,SRX10768326"
    }
  },
  mm10: {
    diff: {
      dataSetA: "SRX7860393,SRX7860394,SRX7860395,SRX7860396,SRX7860397",
      dataSetB: "SRX7860398,SRX7860399,SRX7860400,SRX7860401,SRX7860402,SRX7860403"
    },
    DMR: {
      dataSetA: "SRX2627050,SRX2627051,SRX2627052,SRX2627053",
      dataSetB: "SRX2627054,SRX2627055,SRX2627056,SRX2627057"
    }
  },
  mm9: {
    diff: {
      dataSetA: "SRX7860393,SRX7860394,SRX7860395,SRX7860396,SRX7860397",
      dataSetB: "SRX7860398,SRX7860399,SRX7860400,SRX7860401,SRX7860402,SRX7860403"
    },
    DMR: {
      dataSetA: "SRX2627050,SRX2627051,SRX2627052,SRX2627053",
      dataSetB: "SRX2627054,SRX2627055,SRX2627056,SRX2627057"
    }
  },
  rn6: {
    diff: {
      dataSetA: "SRX10157980,SRX10157981,SRX10157982,SRX10157983,SRX10157984",
      dataSetB: "SRX10158000,SRX10158001,SRX10158002,SRX10158003,SRX10158004,SRX10158005"
    },
    DMR: {
      dataSetA: "SRX10920632,SRX10920633,SRX10920634,SRX10920635",
      dataSetB: "SRX10920622,SRX10920623,SRX10920624,SRX10920625"
    }
  },
  dm6: {
    diff: {
      dataSetA: "SRX7277007,SRX7277008,SRX7277009",
      dataSetB: "SRX7277010,SRX7277011,SRX7277012"
    },
    DMR: {
      dataSetA: "SRX1552727,SRX1552728,SRX1552729,SRX1552730",
      dataSetB: "SRX1552723,SRX1552724,SRX1552725,SRX1552726"
    }
  },
  dm3: {
    diff: {
      dataSetA: "SRX7277007,SRX7277008,SRX7277009",
      dataSetB: "SRX7277010,SRX7277011,SRX7277012"
    },
    DMR: {
      dataSetA: "SRX1552727,SRX1552728,SRX1552729,SRX1552730",
      dataSetB: "SRX1552723,SRX1552724,SRX1552725,SRX1552726"
    }
  },
  ce11: {
    diff: {
      dataSetA: "SRX3029121,SRX3029122,SRX3029123",
      dataSetB: "SRX3029124,SRX3029125,SRX3029126"
    },
    DMR: {
      dataSetA: "",
      dataSetB: ""
    }
  },
  ce10: {
    diff: {
      dataSetA: "SRX3029121,SRX3029122,SRX3029123",
      dataSetB: "SRX3029124,SRX3029125,SRX3029126"
    },
    DMR: {
      dataSetA: "",
      dataSetB: ""
    }
  },
  sacCer3: {
    diff: {
      dataSetA: "SRX4555040,SRX4555064,SRX4555025",
      dataSetB: "SRX4555051,SRX4555039,SRX4555013"
    },
    DMR: {
      dataSetA: "SRX957102,SRX957112,SRX957113",
      dataSetB: "SRX957114,SRX957115,SRX957117"
    }
  }
}

// Diff Analysis post functions
const submitDMR = async () => {
  // diable when blackout
  const endpointStatusUrl = "/wabi_endpoint_status"
  let endpointStatusResponse = await fetch(endpointStatusUrl);
  let endpointStatus = await endpointStatusResponse.text();
  if (endpointStatus == 'chipatlas') {
    $("button#dmr-submit").click(function() {
      $(this).attr("disabled", true); // disable submit button
      const data = retrievePostData();
      $(this).attr("disabled", false); // enable submit button
      const response = postDMR(data);
    });
  } else {
    $("button#dmr-submit").prop("disabled", true);
    alert("DMR analysis is currently unavailable due to the background server issue. See maintainance schedule on top page.");
  }
}

const retrievePostData = () => {
  const genome = genomeSelected();
  const expTypeVal = $('input[name="' + genome + 'DiffOrDMR"]:checked').val();
  let expTypeClass;
  switch (expTypeVal) {
    case 'diff':
      expTypeClass = 'diffbind';
      break;
    case 'DMR':
      expTypeClass = 'dmr';
      break;
  }
  const data = {
    // address: '',
    // qsubOptions: '-N test',
    antigenClass: expTypeClass,
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
    threshold: 5,
    permTime: 1,
  };
  console.log(data);
  return data;
}

const postDMR = async (data) => {
  const genome = genomeSelected();
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
        const redirectUrl = '/diff_analysis_result?id=' + requestId + '&title=' + data['title'] + '&genome=' + genome + '&calcm=' + calcm;
        window.open(redirectUrl, "_self", "");
      },
      error: function(response) {
        console.log(data);
        console.log(response);
        alert("Something went wrong: Please let us know to fix the problem, click 'contact us' below this page." + JSON.stringify(response));
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

// Genome Panel
const setGenomePanel = async () => {
  let genomeListResponse = await fetch('/data/list_of_genome.json');
  let genomeList = await genomeListResponse.json();
  $.each(genomeList, function(i, genome) {
    $('#' + genome + '-tab a').on('click', function(event) {
      event.preventDefault();
      $(this).tab('show');
      putDefaultTitles();
    });
  });
}

// diff analysis time calculation
const estimateTimeOnEdit = () => {
  $('textarea').on('click keyup paste', function() {
    calculateEstimatedTime();
  });
}

const calculateEstimatedTime = () => {
  const genome = genomeSelected();
  const idListA = $('textarea#' + genome + 'DataSetA').val().split(/\r?\n/);
  const idListB = $('textarea#' + genome + 'DataSetB').val().split(/\r?\n/);
  const data = {
    analysis: $('input[name="' + genome + 'DiffOrDMR"]:checked').val(),
    ids: idListA.concat(idListB).filter(item => item !== "")
  }

  $.ajax({
    type: 'post',
    url: "/diff_analysis_estimated_time",
    data: JSON.stringify(data),
    contentType: 'application/json',
    dataType: 'json',
    scriptCharset: 'utf-8',
    success: function(response) {
      const minutes = response.minutes;
      $('a#' + genome + '-estimated-run-time').html(minutes + ' mins');
    },
    error: function(response) {
      console.log(data);
      console.log(response);
      alert("Something went wrong: Please let us know to fix the problem, click 'contact us' below this page." + JSON.stringify(response));
    }
  });
}

const alertHelpMessage = () => {
  $('.infoBtn').click(function() {
    var genome = genomeSelected();
    switch ($(this).attr('id')) {
      case genome + 'DataSetADesc':
        alert(helpText["datasetAdesc"]);
        break;
      case genome + 'DataSetBDesc':
        alert(helpText["datasetBdesc"]);
        break;
      case genome + 'ProjectDesc':
        alert(helpText["projectdesc"]);
        break;
    };
  });
}

const helpText = {
  projectdesc: 'Enter a title for this submission.\nAcceptable letters are alphanumeric (a-Z, 0-9), space ( ), underscore (_), period (.) and hyphen (-).',
  datasetAdesc: 'Enter a title for the data selected in "2. Enter dataset A".\nAcceptable letters are alphanumeric (a-Z, 0-9), space ( ), underscore (_), period (.) and hyphen (-).',
  datasetBdesc: 'Enter a title for the data selected in "3. Enter dataset B".\nAcceptable letters are alphanumeric (a-Z, 0-9), space ( ), underscore (_), period (.) and hyphen (-).',
};
