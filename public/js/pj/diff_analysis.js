window.onload = async () => {
  // load analysis examples
  const examples = await loadExamples();
  console.log(examples);
  // Initialize
  putDefaultTitles();
  submitDMR();
  // Events
  putExampleData(examples);
  switchDataType(examples);
  setGenomePanel();
  estimateTimeOnEdit();
  alertHelpMessage();
};

const loadExamples = async () => {
  const response = await fetch("/diff-analysis.examples.json");
  const examples = await response.json();
  return examples;
};

// UI Building
const putDefaultTitles = () => {
  const defaultTitles = {
    ProjectTitle: "My project",
    DataSetATitle: "dataset A",
    DataSetBTitle: "dataset B",
  };
  const genome = genomeSelected();
  for (const [id, dvalue] of Object.entries(defaultTitles)) {
    const elm = document.getElementById(genome + id);
    elm.value = dvalue;
  }
};

// Change to empty textarea
const switchDataType = (examples) => {
  $("input.diffOrDMR").change(function () {
    eraseTextarea();
    removeExampleIfCEBisulfite(examples);
  });
};

const eraseTextarea = () => {
  const genome = genomeSelected();
  $("textarea#" + genome + "DataSetA").val("");
  $("textarea#" + genome + "DataSetB").val("");
  $("a#" + genome + "-estimated-run-time").html("-");
};

const removeExampleIfCEBisulfite = (examples) => {
  const genome = genomeSelected();
  if (genome.startsWith("ce")) {
    // Remove anker tag if DMR is checked
    if ($("input#" + genome + "ExpTypeDMR").prop("checked")) {
      // placeholder
      $("textarea#" + genome + "DataSetA").attr("placeholder", "");
      $("textarea#" + genome + "DataSetB").attr("placeholder", "");
      // anker
      $("a.dataExample#" + genome + "dataSetA").replaceWith(
        '<p id="' + genome + 'dataSetA">no public data available</p>',
      );
      $("a.dataExample#" + genome + "dataSetB").replaceWith(
        '<p id="' + genome + 'dataSetB">no public data available</p>',
      );
    } else {
      // revert placeholder
      $("textarea#" + genome + "DataSetA").attr(
        "placeholder",
        "SRX or GSM ID(s)",
      );
      $("textarea#" + genome + "DataSetB").attr(
        "placeholder",
        "SRX or GSM ID(s)",
      );
      // revert anker
      $("p#" + genome + "dataSetA").replaceWith(
        '<a class="dataExample" href="#" id="' +
          genome +
          'dataSetA" name="dataSetA">Try with example</a>',
      );
      $("p#" + genome + "dataSetB").replaceWith(
        '<a class="dataExample" href="#" id="' +
          genome +
          'dataSetB" name="dataSetB">Try with example</a>',
      );
      // Enable example data insertion
      putExampleData(examples);
    }
  }
};

// Example data
const putExampleData = (examples) => {
  $("a.dataExample").on("click", function (event) {
    event.preventDefault();
    event.stopPropagation();
    const genome = genomeSelected();
    const expType = $('input[name="' + genome + 'DiffOrDMR"]:checked').val();
    let set = $(this).attr("name");
    const species = genome.replace(/\d+$/, "");
    let examplesString = examples[species][expType][set].join("\n");
    switch (set) {
      case "dataSetA":
        $("textarea#" + genome + "DataSetA").val(examplesString);
        break;
      case "dataSetB":
        $("textarea#" + genome + "DataSetB").val(examplesString);
        break;
    }
    calculateEstimatedTime();
  });
};

// Diff Analysis post functions
const submitDMR = async () => {
  // diable when blackout
  const endpointStatusUrl = "/wabi_endpoint_status";
  let endpointStatusResponse = await fetch(endpointStatusUrl);
  let endpointStatus = await endpointStatusResponse.text();
  if (endpointStatus == "chipatlas") {
    $("button#dmr-submit").click(function () {
      $(this).attr("disabled", true); // disable submit button
      const data = retrievePostData();
      $(this).attr("disabled", false); // enable submit button
      const response = postDMR(data);
    });
  } else {
    $("button#dmr-submit").prop("disabled", true);
    alert(
      "Diff analysis is currently unavailable due to the background server issue. See maintainance schedule on top page.",
    );
  }
};

const retrievePostData = () => {
  const genome = genomeSelected();
  const expTypeClass = $('input[name="' + genome + 'DiffOrDMR"]:checked').val();
  const data = {
    // address: '',
    // qsubOptions: '-N test',
    antigenClass: expTypeClass,
    title: $("input#" + genome + "ProjectTitle").val(),
    genome: genome,
    typeA: "srx",
    bedAFile: $("textarea#" + genome + "DataSetA").val(),
    descriptionA: $("input#" + genome + "DataSetATitle").val(),
    typeB: "srx",
    bedBFile: $("textarea#" + genome + "DataSetB").val(),
    descriptionB: $("input#" + genome + "DataSetBTitle").val(),
    format: "text",
    result: "www",
    cellClass: "empty",
    threshold: 5,
    permTime: 1,
  };
  if (data.antigenClass == "dmc" || data.antigenClass == "diffbind") {
    data.sbatchOptions = "-p epyc -t 3:00:00";
  }
  console.log(data);
  return data;
};

const postDMR = async (data) => {
  const genome = genomeSelected();
  const endpointUrl = "/wabi_chipatlas";
  try {
    $.ajax({
      type: "post",
      url: "/wabi_chipatlas",
      data: JSON.stringify(data),
      contentType: "application/json",
      dataType: "json",
      scriptCharset: "utf-8",
      success: function (response) {
        const requestId = response.requestId;
        const calcm = $("a#" + genome + "-estimated-run-time")
          .text()
          .replace(/-/g, "");
        const redirectUrl =
          "/diff_analysis_result?id=" +
          requestId +
          "&title=" +
          data["title"] +
          "&genome=" +
          genome +
          "&calcm=" +
          calcm;
        window.open(redirectUrl, "_self", "");
      },
      error: function (response) {
        console.log(data);
        console.log(response);
        alert(
          "Something went wrong: Please let us know to fix the problem, click 'contact us' below this page." +
            JSON.stringify(response),
        );
      },
      complete: function () {
        button.attr("disabled", false);
      },
    });
  } catch (e) {
    alert(e.message);
    button.prop("disabled", false);
  }
};

// Genome Panel
const setGenomePanel = async () => {
  let genomeListResponse = await fetch("/data/list_of_genome.json");
  let genomeList = await genomeListResponse.json();
  $.each(genomeList, function (i, genome) {
    $("#" + genome + "-tab a").on("click", function (event) {
      event.preventDefault();
      $(this).tab("show");
      putDefaultTitles();
    });
  });
};

// diff analysis time calculation
const estimateTimeOnEdit = () => {
  $("textarea").on("click keyup paste", function () {
    calculateEstimatedTime();
  });
};

const calculateEstimatedTime = () => {
  const genome = genomeSelected();
  const idListA = $("textarea#" + genome + "DataSetA")
    .val()
    .split(/\r?\n/);
  const idListB = $("textarea#" + genome + "DataSetB")
    .val()
    .split(/\r?\n/);
  const data = {
    analysis: $('input[name="' + genome + 'DiffOrDMR"]:checked').val(),
    ids: idListA.concat(idListB).filter((item) => item !== ""),
  };

  $.ajax({
    type: "post",
    url: "/diff_analysis_estimated_time",
    data: JSON.stringify(data),
    contentType: "application/json",
    dataType: "json",
    scriptCharset: "utf-8",
    success: function (response) {
      const minutes = response.minutes;
      $("a#" + genome + "-estimated-run-time").html(minutes + " mins");
    },
    error: function (response) {
      console.log(data);
      console.log(response);
      alert(
        "Something went wrong: Please let us know to fix the problem, click 'contact us' below this page." +
          JSON.stringify(response),
      );
    },
  });
};

const alertHelpMessage = () => {
  $(".infoBtn").click(function () {
    var genome = genomeSelected();
    switch ($(this).attr("id")) {
      case genome + "DataSetADesc":
        alert(helpText["datasetAdesc"]);
        break;
      case genome + "DataSetBDesc":
        alert(helpText["datasetBdesc"]);
        break;
      case genome + "ProjectDesc":
        alert(helpText["projectdesc"]);
        break;
    }
  });
};

const helpText = {
  projectdesc:
    "Enter a title for this submission.\nAcceptable letters are alphanumeric (a-Z, 0-9), space ( ), underscore (_), period (.) and hyphen (-).",
  datasetAdesc:
    'Enter a title for the data selected in "2. Enter dataset A".\nAcceptable letters are alphanumeric (a-Z, 0-9), space ( ), underscore (_), period (.) and hyphen (-).',
  datasetBdesc:
    'Enter a title for the data selected in "3. Enter dataset B".\nAcceptable letters are alphanumeric (a-Z, 0-9), space ( ), underscore (_), period (.) and hyphen (-).',
};
