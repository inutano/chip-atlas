// variables
// switch enrichment analysis API endpoint if this constant is set to the IP address of the server
const sapporoService = "52.69.0.138:1122";

const genomesize = {
  ce10: 100286070,
  ce11: 100286070,
  dm3: 168736537,
  dm6: 168736537,
  hg19: 3137161264,
  hg38: 3137161264,
  mm9: 2725765481,
  mm10: 2725765481,
  sacCer3: 12157105,
  rn6: 2870182909,
};

const numGenes = {
  ce10: 17958,
  ce11: 17958,
  dm3: 12635,
  dm6: 12635,
  hg19: 18622,
  hg38: 18622,
  mm9: 19909,
  mm10: 19909,
  sacCer3: 5809,
  rn6: 23425,
};

const taxidMap = {
  9606: {
    organismName: "Homo sapiens",
    displayName: "H. sapiens",
    genomeVersions: ["hg19", "hg38"],
  },
  10090: {
    organismName: "Mus musculus",
    displayName: "M. musculus",
    genomeVersions: ["mm9", "mm10"],
  },
  10116: {
    organismName: "Rattus norvegicus",
    displayName: "R. norvegicus",
    genomeVersions: ["rn6"],
  },
  7227: {
    organismName: "Drosophila melanogaster",
    displayName: "D. melanogaster",
    genomeVersions: ["dm3", "dm6"],
  },
  6239: {
    organismName: "Caenorhabditis elegans",
    displayName: "C. elegans",
    genomeVersions: ["ce10", "ce11"],
  },
  4932: {
    organismName: "Saccharomyces cerevisiae",
    displayName: "S. cerevisiae",
    genomeVersions: ["sacCer3"],
  },
};

// onload
window.onload = async () => {
  generateExperimentTypeOptions();
  generateSampleTypeOptions();

  // default value for dataset
  putDefaultTitles();

  // qvalue options
  generateQvalOptions();

  // Form Layout: User Data
  $("input[name='bedORGene']").change(function () {
    var genome = genomeSelected();
    switch ($(this).val()) {
      case "bed":
        positionBed();
        break;
      case "gene":
        positionGene();
        break;
    }
    eraseTextarea(genome + "UserData");
  });

  // Form Layout: Compared With
  $("input[name='comparedWith']").change(function () {
    var genome = genomeSelected();
    switch ($(this).val()) {
      case "rnd":
        positionComparedRnd();
        break;
      case "bed":
        positionComparedBed();
        break;
      case "refseq":
        positionComparedRefseq();
        break;
      case "userlist":
        positionComparedUserlist();
        break;
    }
    eraseTextarea(genome + "ComparedWith");
  });

  // check the endpoint status if the constant sapporoService is not set
  if (sapporoService === "") {
    let endpointStatusResponse = await fetch("/wabi_endpoint_status");
    let endpointStatus = await endpointStatusResponse.text();
    if (endpointStatus == "chipatlas") {
      $("button#virtual-chip-submit").click(function () {
        var button = $(this);
        var data = retrievePostData();
        post2wabi(button, data);
      });
    } else {
      $("button#virtual-chip-submit").prop("disabled", true);
      alert(
        "Enrichment analysis is currently unavailable due to the background server issue. See maintainance schedule on top page.",
      );
    }
  } else {
    $("button#virtual-chip-submit").click(function () {
      var button = $(this);
      var data = retrievePostData();
      post2sapporo(button, data);
    });
  }

  // calculate estimated running time
  // get reference of #lines of bed files
  let numRefResponse = await fetch("/data/number_of_lines.json");
  let numRef = await numRefResponse.json();

  $("input, select, textarea").on("click keyup paste", function () {
    timeCalculate(numRef);
  });
  // example data
  $("a.dataExample").on("click", function (event) {
    event.preventDefault();
    event.stopPropagation();
    var id = $(this).attr("id");
    putExampleData(id);
    timeCalculate(numRef);
  });

  // iterate for each genome
  let genomeListResponse = await fetch("/data/list_of_genome.json");
  let genomeList = await genomeListResponse.json();

  $.each(genomeList, function (i, genome) {
    changeSelect(genome);
    // set tab controller
    $("#" + genome + "-tab a").on("click", function (e) {
      e.preventDefault();
      $(this).tab("show");
      positionBed();
      generateExperimentTypeOptions();
      generateSampleTypeOptions();
      putDefaultTitles();
      generateQvalOptions();
    });
    // put file content into the textarea
    $(
      "input#" + genome + "UserDataFile, input#" + genome + "ComparedWithFile",
    ).on("change", function (event) {
      var fileId = $(this).attr("id");
      putFile2Textarea(fileId, event, timeCalculate.bind(this, numRef));
    });
    // $('a[data-toggle="tab"]').on('shown.bs.tab', function(e) {
    //   var activatedTab = e.target;
    //   var previousTab = e.relatedTarget;
    // });
  });

  // Q & A
  $(".infoBtn").click(function () {
    var genome = genomeSelected();
    switch ($(this).attr("id")) {
      case genome + "UserDataBed":
        alert(helpText["userdatabed"] + helpText["note2"]);
        break;
      case genome + "UserDataGenes":
        alert(helpText["userdatagenes"] + helpText["note1"]);
        break;
      case genome + "ComparedWithRandom":
        alert(helpText["comparedwithrandom"]);
        break;
      case genome + "ComparedWithBed":
        alert(helpText["comparedwithbed"] + helpText["note2"]);
        break;
      case genome + "ComparedWithRefseq":
        alert(helpText["comparedwithrefseq"]);
        break;
      case genome + "ComparedWithUserlist":
        alert(helpText["comparedwithuserlist"] + helpText["note1"]);
        break;
      case genome + "TSS":
        alert(helpText["tss"]);
        break;
      case genome + "UserDataDesc":
        alert(helpText["userdatadesc"]);
        break;
      case genome + "ComparedWithDesc":
        alert(helpText["comparedwithdesc"]);
        break;
      case genome + "ProjectDesc":
        alert(helpText["projectdesc"]);
        break;
      case genome + "DistTSS":
        alert(helpText["disttss"]);
        break;
      case genome + "Threshold":
        alert(helpText["threshold"]);
        break;
    }
  });

  const params = JSON.parse($("#ea_params").html());
  const genes = decodeURI(params["genes"]);
  const genesetA = decodeURI(params["genesetA"]);
  const genesetB = decodeURI(params["genesetB"]);
  const taxid = params["taxonomy"];

  if (taxid !== "") {
    const taxonomy = taxidMap[taxid]["genomeVersions"][0]; // TODO: Add genome assembly parameter for POST option

    $('[href="#' + taxonomy + '-tab-content"]').tab("show");
    if (genes !== "") {
      $("input[id='" + taxonomy + "UserDataGenes']").prop("checked", true);
      positionGene();
      $("textarea[id='" + taxonomy + "UserData']").append(genes);
    } else if (genesetA !== "" && genesetB !== "") {
      // Check "Gene list" in panel 4, change layout, append gene list
      $("input[id='" + taxonomy + "UserDataGenes']").prop("checked", true);
      positionGene();
      $("textarea[id='" + taxonomy + "UserData']").append(genesetA);
      // Check "Gene list" in panel 5, change layout, append gene list
      $("input[id='" + taxonomy + "ComparedWithUserlist']").prop(
        "checked",
        true,
      );
      positionComparedUserlist();
      $("textarea[id='" + taxonomy + "ComparedWith']").append(genesetB);
    }
  }
};

// functions
const changeSelect = (genome) => {
  const agSelectElement = document.querySelector("#" + genome + "agClass");
  agSelectElement.addEventListener("change", (event) => {
    generateSampleTypeOptions();
    generateQvalOptions();
  });
};

const generateExperimentTypeOptions = async () => {
  const genome = genomeSelected();
  const clSelected = $("select#" + genome + "clClass option:selected").val();

  const select = $("select#" + genome + "agClass");
  select.empty();

  let response = await fetch(
    "/data/experiment_types?genome=" + genome + "&clClass=" + clSelected,
  );
  let experimentList = await response.json();

  experimentList.forEach((experiment, i) => {
    let id = experiment["id"];
    let label = experiment["label"];
    let count = experiment["count"];
    let option = $("<option>")
      .attr("value", id)
      .append(label + " (" + count + ")");
    if (i == 0) option.attr("selected", true);

    // don't add annotation tracks
    if (label != "Annotation tracks") {
      option.appendTo(select);
    }
  });

  let numRefResponse = await fetch("/data/number_of_lines.json");
  let numRef = await numRefResponse.json();
  timeCalculate(numRef);
};

const generateSampleTypeOptions = async () => {
  const genome = genomeSelected();
  const agSelected = $("select#" + genome + "agClass option:selected").val();

  const select = $("select#" + genome + "clClass");
  select.empty();

  let response = await fetch(
    "/data/sample_types?genome=" + genome + "&agClass=" + agSelected,
  );
  let sampleList = await response.json();

  sampleList.forEach((experiment, i) => {
    let id = experiment["id"];
    let label = experiment["label"];
    let count = experiment["count"];
    let option = $("<option>")
      .attr("value", id)
      .append(label + " (" + count + ")");
    if (i == 0) option.attr("selected", true);
    option.appendTo(select);
  });

  let numRefResponse = await fetch("/data/number_of_lines.json");
  let numRef = await numRefResponse.json();
  timeCalculate(numRef);
};

function putDefaultTitles() {
  var defaultTitles = {
    UserDataTitle: "dataset A",
    ComparedWithTitle: "Control",
    ProjectTitle: "My project",
  };
  $.each(defaultTitles, function (id, dvalue) {
    setInputDefaultValue(id, dvalue);
  });
}

function putExampleData(id) {
  var genome = genomeSelected();
  var type;
  switch (id) {
    case genome + "UserData":
      type = $(
        "#" + genome + '-tab-content input[name="bedORGene"]:checked',
      ).val();
      putUserData(type);
      break;
    case genome + "ComparedWith":
      type = $(
        "#" + genome + '-tab-content input[name="comparedWith"]:checked',
      ).val();
      putComparedWith(type);
      break;
  }
}

function putUserData(type) {
  var genome = genomeSelected();
  switch (type) {
    case "bed":
      getExampleData(genome, "bedA.txt", genome + "UserData");
      break;
    case "gene":
      getExampleData(genome, "geneA.txt", genome + "UserData");
      break;
  }
}

function putComparedWith(type) {
  var genome = genomeSelected();
  switch (type) {
    case "bed":
      getExampleData(genome, "bedB.txt", genome + "ComparedWith");
      break;
    case "userlist":
      getExampleData(genome, "geneB.txt", genome + "ComparedWith");
      break;
  }
}

function getExampleData(genome, fname, textareaId) {
  $.ajax({
    type: "GET",
    url: "/examples/" + genome + "/" + fname,
    success: function (data) {
      $("textarea#" + textareaId).val(data);
    },
  });
}

function positionBed() {
  var panels = {
    ".panel-input.bed": "show",
    ".panel-input.rnd": "show",
    ".panel-input.gene.default-hide": "hide",
    ".panel-input.distTSS": "hide",
    ".panel-input.bed-input.comparedWith": "hide",
  };
  var inputs = {
    ComparedWithRandom: "checked",
    ComparedWithRandomx1: "checked",
    ComparedWithBed: "unchecked",
    ComparedWithRefseq: "unchecked",
    ComparedWithUserlist: "unchecked",
  };
  setForms(panels, inputs);
  setDistance(0);
}

function positionGene() {
  var panels = {
    ".panel-input.rnd": "show",
    ".panel-input.distTSS": "show",
    ".panel-input.gene.default-hide": "show",
    ".panel-input.bed": "hide",
    ".panel-input.bed-input.comparedWith": "hide",
  };
  var inputs = {
    ComparedWithRefseq: "checked",
    ComparedWithBed: "unchecked",
    ComparedWithRandom: "unchecked",
    ComparedWithRandomx1: "unchecked",
    ComparedWithUserlist: "unchecked",
  };
  setForms(panels, inputs);
  setDistance(5000);
}

function setForms(panels, inputs) {
  $.each(panels, function (id, type) {
    hideAndShow(id, type);
  });
  $.each(inputs, function (id, type) {
    inputChange(id, type);
  });
}

function hideAndShow(element, type) {
  switch (type) {
    case "show":
      $(element).show();
      break;
    case "hide":
      $(element).hide();
      break;
  }
}

function inputChange(id, type) {
  var genome = genomeSelected();
  switch (type) {
    case "checked":
      $("input#" + genome + id).prop("checked", true);
      break;
    case "unchecked":
      $("input#" + genome + id).prop("checked", false);
      break;
  }
}

function setDistance(distValue) {
  var genome = genomeSelected();
  $("input#" + genome + "DistanceUp").val(distValue);
  $("input#" + genome + "DistanceDown").val(distValue);
}

function positionComparedRnd() {
  var panels = {
    ".panel-input.rnd": "show",
    ".panel-input.gene.default-hide": "hide",
    ".panel-input.bed-input.comparedWith": "hide",
  };
  var inputs = {};
  setForms(panels, inputs);
}

function positionComparedBed() {
  var panels = {
    ".panel-input.rnd": "hide",
    ".panel-input.bed-input.comparedWith": "show",
  };
  var inputs = {};
  setForms(panels, inputs);
}

function positionComparedRefseq() {
  var panels = {
    ".panel-input.gene.default-hide": "show",
    ".panel-input.bed-input.comparedWith": "hide",
  };
  var inputs = {};
  setForms(panels, inputs);
}

function positionComparedUserlist() {
  var panels = {
    ".panel-input.bed-input.comparedWith": "show",
  };
  var inputs = {};
  setForms(panels, inputs);
}

function eraseTextarea(textareaId) {
  $("textarea#" + textareaId).val("");
}

function retrievePostData() {
  var genome = genomeSelected();
  var permTime = $(
    "#" + genome + '-tab-content input[name="numShuf"]:checked',
  ).val();
  permTime = permTime > 0 ? permTime : 1;
  var data = {
    address: "",
    format: "text",
    result: "www",
    qsubOptions: "-N test",
    genome: genome,
    antigenClass: $("select#" + genome + "agClass option:selected").val(),
    cellClass: $("select#" + genome + "clClass option:selected").val(),
    threshold: $("select#" + genome + "qval option:selected").val(),
    typeA: $(
      "#" + genome + '-tab-content input[name="bedORGene"]:checked',
    ).val(),
    bedAFile: $("textarea#" + genome + "UserData").val(),
    typeB: $(
      "#" + genome + '-tab-content input[name="comparedWith"]:checked',
    ).val(),
    bedBFile: retrieveInputData("ComparedWith"),
    permTime: permTime,
    title: $("input#" + genome + "ProjectTitle").val(),
    descriptionA: $("input#" + genome + "UserDataTitle").val(),
    descriptionB: $("input#" + genome + "ComparedWithTitle").val(),
    distanceUp: $("input#" + genome + "DistanceUp").val(),
    distanceDown: $("input#" + genome + "DistanceDown").val(),
  };
  return data;
}

function retrieveInputData(type) {
  var genome = genomeSelected();
  var flatfile;
  var inputText = $("textarea#" + genome + type).val();
  if (inputText == "") {
    flatfile = "empty";
  } else {
    flatfile = inputText;
  }
  return flatfile;
}

function evaluateText(data) {
  var descSet = [
    [data["bedAFile"], "bed", "User data bed file"],
    [data["descriptionA"], "desc", "User data title"],
    [data["bedBFile"], "bed", "Compared data bed file"],
    [data["descriptionB"], "desc", "Compared data title"],
    [data["distanceUp"], "dist", "Distance down range"],
    [data["distanceDown"], "dist", "Distance up range"],
    [data["title"], "desc", "Project title"],
  ];
  var allowedChars = {
    bed: "alphanumerics, tab, underscore(_)",
    desc: "- alphanumerics (abcABC123)\n- space ( )\n- underscore (_)\n- period (.)\n- hyphen (-)",
    dist: "- positive integer (1,2,3,..)",
  };
  $.each(descSet, function (i, set) {
    if (isValid(set[0], set[1]) != true) {
      //alert("Invalid characters detected. Allowed characters are;\n"+allowedChars(set[0]));
      throw new Error(
        "Invalid characters are detected in " +
          set[2] +
          ". Acceptable characters are:\n" +
          allowedChars[set[1]],
      );
    }
  });
}

function isValid(string, type) {
  var regexp;
  switch (type) {
    case "bed":
      //  regexp = /[A-Za-z0-9\t_]/g;
      regexp = /.*/g; // currently not filtered
      break;
    case "desc":
      regexp = /[A-Za-z0-9_.-\s]/g;
      break;
    case "dist":
      regexp = /[0-9]/g;
      break;
  }
  var filtered = string.replace(/\n/g, "").replace(regexp, "");
  if (filtered === "") {
    return true;
  }
}

function replaceDataChars(data) {
  data["bedAFile"] = data["bedAFile"].replace(/[^a-zA-Z0-9\t_\n]/g, "_");
  data["bedBFile"] = data["bedBFile"].replace(/[^a-zA-Z0-9\t_\n]/g, "_");
  return data;
}

function convertJsonStringsToIntegers(data) {
  data.permTime = parseInt(data.permTime, 10);
  data.threshold = parseInt(data.threshold, 10);
  data.distanceDown = parseInt(data.distanceDown, 10);
  data.distanceUp = parseInt(data.distanceUp, 10);
  return data;
}

function post2sapporo(button, data) {
  var genome = genomeSelected();
  button.attr("disabled", true);
  // evaluate text input and reject if invalid characters are found
  try {
    evaluateText(data);
    replaceDataChars(data);
    convertJsonStringsToIntegers(data);

    var formData = new FormData();
    formData.append("workflow_type", "enrichment-analysis");
    formData.append("workflow_engine", "enrichment-analysis");
    formData.append("workflow_params", JSON.stringify(data));
    $.ajax({
      type: "post",
      url: "http://" + sapporoService + "/runs",
      data: formData,
      contentType: false,
      processData: false,
      success: function (response) {
        var requestId = response.run_id;
        var calcm = $("a#" + genome + "-estimated-run-time")
          .text()
          .replace(/-/g, "");
        var redirectUrl =
          "/enrichment_analysis_result?id=" +
          requestId +
          "&api=" +
          sapporoService +
          "&title=" +
          data["title"] +
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
}

function post2wabi(button, data) {
  var genome = genomeSelected();
  button.attr("disabled", true);
  // evaluate text input and reject if invalid characters are found
  try {
    evaluateText(data);
    data = replaceDataChars(data);
    $.ajax({
      type: "post",
      url: "/wabi_chipatlas",
      data: JSON.stringify(data),
      contentType: "application/json",
      dataType: "json",
      scriptCharset: "utf-8",
      success: function (response) {
        var requestId = response.requestId;
        var calcm = $("a#" + genome + "-estimated-run-time")
          .text()
          .replace(/-/g, "");
        var redirectUrl =
          "/enrichment_analysis_result?id=" +
          requestId +
          "&api=wabi" +
          "&title=" +
          data["title"] +
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
        //alert("Error: DDBJ supercomputer now unavailable: http://www.ddbj.nig.ac.jp/whatsnew");
      },
      complete: function () {
        button.attr("disabled", false);
      },
    });
  } catch (e) {
    alert(e.message);
    button.prop("disabled", false);
  }
}

function timeCalculate(numRef) {
  var genome = genomeSelected();
  var userData = $("textarea#" + genome + "UserData").val();
  var comparedWith = $("textarea#" + genome + "ComparedWith").val();
  var ag = $("select#" + genome + "agClass").val();
  var cl = $("select#" + genome + "clClass").val();
  var qval = $("select#" + genome + "qval").val() / 10;
  if (ag == "Bisulfite-Seq") {
    var qval = "bs";
  } else if (qval == 5) {
    var qval = "0" + 5;
  }
  var qBed = genome + "," + ag + "," + cl + "," + qval;
  var numRef = numRef[qBed];
  var est = estimateTime(userData, comparedWith, numRef);
  $("a#" + genome + "-estimated-run-time").html(est);
}

function estimateTime(userData, comparedWith, numRef) {
  // userData: string, text pasted in bottom-left panel
  // comparedWith: string, text pasted in bottom-right panel
  // numRef: integer, number calculated for each combination of genome/antigen/cell line in advance
  var lf = String.fromCharCode(10);
  var genome = genomeSelected();
  // set #lines of user data (bottom-left panel)
  var numLinesUserData;
  if (userData.length == 0) {
    numLinesUserData = 0;
  } else {
    numLinesUserData = userData.replace(/\n$/g, "").split(lf).length;
  }
  // set #lines of compared with (bottom-right panel)
  var numLinesComparedWith;
  if (comparedWith.length == 0) {
    numLinesComparedWith = 0;
  } else {
    numLinesComparedWith = comparedWith.replace(/\n$/g, "").split(lf).length;
  }
  switch (
    $("#" + genome + '-tab-content input[name="bedORGene"]:checked').val()
  ) {
    case "bed":
      if (numLinesUserData == 1 && !userData.match(/\t/)) {
        // sequence motif
        numLinesUserData = genomesize[genome] / Math.pow(4, userData.length);
      }
      switch (
        $(
          "#" + genome + '-tab-content input[name="comparedWith"]:checked',
        ).val()
      ) {
        case "rnd":
          numLinesComparedWith = $(
            "#" + genome + '-tab-content input[name="numShuf"]:checked',
          ).val();
          var seconds = getSeconds(
            numLinesUserData,
            numLinesComparedWith,
            numRef,
            "rnd",
          );
          break;
        case "bed":
          if (numLinesComparedWith == 1 && !comparedWith.match(/\t/)) {
            numLinesComparedWith =
              genomesize[genome] / Math.pow(4, comparedWith.length);
          }
          var seconds = getSeconds(
            numLinesUserData,
            numLinesComparedWith,
            numRef,
            "bed",
          );
          break;
      }
      break;
    case "gene":
      switch (
        $(
          "#" + genome + '-tab-content input[name="comparedWith"]:checked',
        ).val()
      ) {
        case "refseq":
          numLinesComparedWith = numGenes[genome] - numLinesUserData;
          var seconds = getSeconds(
            numLinesUserData,
            numLinesComparedWith,
            numRef,
            "bed",
          );
          break;
        case "userlist":
          var seconds = getSeconds(
            numLinesUserData,
            numLinesComparedWith,
            numRef,
            "bed",
          );
          break;
      }
      break;
  }
  var minutes = Math.round(seconds / 60);
  if (minutes < 60) {
    var est = minutes + " mins";
  } else {
    var est = (minutes / 60).toFixed(1) + " hr";
  }
  return est;
}

function getSeconds(numLinesA, numLinesB, numRef, type) {
  switch (type) {
    case "bed":
      var a = numRef * 8.23e-11 + 1.47e-2;
      var b = numRef * 4.72e-11 + 7.24e-3;
      var c = (numLinesA + numLinesB) * 6.75e-11 + 1.02e-6;
      var k = 60;
      var seconds = (k + a * numLinesA + b * numLinesB + c * numRef) * (5 / 7);
      return seconds;
    default:
      var a = numRef * 3.02e-12 + 1.13e-4;
      var c = (numLinesA + numLinesA * numLinesB) * 3.02e-12 + 2.06e-6;
      var k = 20;
      var seconds =
        1.8 *
        Math.pow(
          k +
            a * (Math.pow(0.8 * numLinesA, 1.52) + numLinesA * numLinesB) +
            c * numRef,
          0.85,
        );
      return seconds;
  }
}

function setInputDefaultValue(id, dvalue) {
  var genome = genomeSelected();
  $("input#" + genome + id).val(dvalue);
}

function putFile2Textarea(fileId, event, callback) {
  var genome = genomeSelected();
  var file = event.target.files;
  var reader = new FileReader();
  reader.readAsText(file[0]);
  reader.onload = function (ev) {
    if (fileId == genome + "UserDataFile") {
      $("textarea#" + genome + "UserData").val(reader.result);
    } else if (fileId == genome + "ComparedWithFile") {
      $("textarea#" + genome + "ComparedWith").val(reader.result);
    }
    callback();
  };
}

const generateQvalOptions = async () => {
  const genome = genomeSelected();

  const select = document.getElementById(genome + "qval");
  document
    .querySelectorAll("#" + genome + "qval option")
    .forEach((option) => option.remove());

  const agSelected = $("select#" + genome + "agClass option:selected").val();
  switch (agSelected) {
    case "Bisulfite-Seq":
      const opt = document.createElement("option");
      opt.setAttribute("value", 999);
      opt.setAttribute("selected", "true");

      const val = document.createTextNode("NA");
      opt.appendChild(val);
      select.appendChild(opt);
      break;
    default:
      let response = await fetch("/qvalue_range");
      let qvList = await response.json();
      qvList.forEach((qv, i) => {
        let opt = document.createElement("option", { value: qv });
        if (i == 0) opt.setAttribute("selected", "true");
        let val = document.createTextNode(parseInt(qv) * 10);
        opt.appendChild(val);
        select.appendChild(opt);
      });
  }

  let numRefResponse = await fetch("/data/number_of_lines.json");
  let numRef = await numRefResponse.json();
  timeCalculate(numRef);
};

// should be exported to json file
var helpText = {
  note1:
    "Acceptable identifiers:\n  Official gene symbols (e.g. POU5F1)\n  Ensembl IDs (e.g. ENSG00000204531)\n  Uniprot IDs (e.g. Q01860)\n  RefSeq gene IDs (e.g. NM_002701)\n\nOfficial gene symbols must be entered according to following nomenclatures:\n  H. sapiens: HGNC\n  M. musculus: MGI\n  R. norvegicus: RGD\n  D. melanogaster: FlyBase\n  C. elegans: WormBase\n  S. cerevisiae: SGD\n\nAcceptable example:\n  POU5F1\n  TP53\n\nBad example:\n  OCT4\n  p53",
  note2:
    "Example:\n  chr1\t531435\t543845\n  chr2\t738543\t742321\n\n  Acceptable genome assemblies:\n    hg19, hg38 (H. sapiens)\n    mm9, mm10 (M. musculus)\n    rn6 (R. norvegicus)\n    dm3, dm6 (D. melanogaster)\n    ce10, ce11 (C. elegans)\n    sacCer3 (S. cerevisiae)\n\n",
  userdatabed:
    "Check this to search for common epigenetic features within given genomic regions (UCSC BED format).\n\n",
  userdatagenes:
    "Check this to search for common epigenetic features around given genes.\n\n",
  comparedwithrandom:
    "Check this to compare ‘dataset A’ with a random background. In this case, each genomic location of ‘dataset A’ is permuted on a random chromosome at a random position for the specified times. Increasing the permutation times will provide a highly randomized background, or a high quality statistical test, but the calculation time will be longer.",
  comparedwithbed:
    "Check this to compare 'dataset A' with another dataset (UCSC BED format).\n\n",
  comparedwithrefseq:
    "Check this to compare 'dataset A' with RefSeq coding genes, excluding those listed in 'dataset A'.",
  comparedwithuserlist:
    "Check this to compare 'dataset A' with another gene list.\n\n",
  tss: "To search for common epigenetic features around given genes, specify the distance range from the Transcription Start Sites (TSS).\nDefault is between -5000 and +5000 bp from the TSS.",
  userdatadesc:
    'Enter a title for the data selected in "4. Enter dataset A".\nAcceptable letters are alphanumeric (a-Z, 0-9), space ( ), underscore (_), period (.) and hyphen (-).',
  comparedwithdesc:
    'Enter a title for the data selected in "5. Enter dataset B".\nAcceptable letters are alphanumeric (a-Z, 0-9), space ( ), underscore (_), period (.) and hyphen (-).',
  projectdesc:
    "Enter a title for this submission.\nAcceptable letters are alphanumeric (a-Z, 0-9), space ( ), underscore (_), period (.) and hyphen (-).",
  disttss:
    "To search for common epigenetic features around given genes, specify the distance range from the Transcription Start Sites (TSS).\nDefault is between -5000 and +5000 bp from the TSS.",
  threshold:
    "Set the threshold for statistical significance values calculated by peak-caller MACS2 (-10*Log10[MACS2 Q-value]). If set to 50, peaks with Q values < 1E-05 are used to evaluate overlap with data sets A and B. Ignore if experiment type is set to Bisulfite-seq.",
};
