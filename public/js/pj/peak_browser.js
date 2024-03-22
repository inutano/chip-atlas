window.onload = () => {
  initOptions();
  peakBrowserTabTriggerEvents();
  genomeTabSettings();
  setForm();
  showHelp();
};

const initOptions = () => {
  generateExperimentTypeOptions();
  generateSampleTypeOptions();
  generateChIPAntigenOptions();
  generateCellTypeOptions();
  generateQvalOptions();
};

const peakBrowserTabTriggerEvents = () => {
  $('a[data-toggle="tab"]').on("shown.bs.tab", function (e) {
    initOptions();
  });
};

/*
    Antigen/Cell type parent Class option generation
*/

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
    option.appendTo(select);
  });
};

const generateSampleTypeOptions = async () => {
  const genome = genomeSelected();
  const agSelected = $("select#" + genome + "agClass option:selected").val(); // send undefined when loading window / tab

  const select = $("select#" + genome + "clClass");
  select.empty();

  let response = await fetch(
    "/data/sample_types?genome=" + genome + "&agClass=" + agSelected,
  );
  let sampleList = await response.json();

  switch (agSelected) {
    case "Annotation tracks":
      let option = $("<option>")
        .attr("value", "NA")
        .attr("selected", true)
        .append("NA");
      option.appendTo(select);
      break;
    default:
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
  }
};

/*
     Antigen/Cell type SubClass option generation
*/

const generateChIPAntigenOptions = async () => {
  const genome = genomeSelected();
  const agSelected = $("select#" + genome + "agClass option:selected").val();
  const clSelected = $("select#" + genome + "clClass option:selected").val();

  const select = $("select#" + genome + "agSubClass");
  select.empty();

  switch (agSelected) {
    case "Input control":
    case "ATAC-Seq":
    case "DNase-seq":
    case "Bisulfite-Seq":
      // put 'NA'
      $("<option>")
        .attr("value", "-")
        .attr("selected", true)
        .append("NA")
        .appendTo(select);
      break;
    default:
      let response = await fetch(
        "/data/chip_antigen?genome=" +
          genome +
          "&agClass=" +
          agSelected +
          "&clClass=" +
          clSelected,
      );
      let agList = await response.json();

      agList.forEach((experiment, i) => {
        let id = experiment["id"];
        let label = experiment["label"];
        let count = experiment["count"];
        let option = $("<option>").attr("value", id);

        switch (agSelected) {
          case "Annotation tracks":
            if (i == 0) {
              // option.append(label).attr("selected", true);
            } else if (i == 1) {
              option.append(label).attr("selected", true);
              option.appendTo(select);
            } else {
              option.append(label);
              option.appendTo(select);
            }
            break;
          default:
            if (i == 0) {
              option.append(label).attr("selected", true);
              option.appendTo(select);
            } else {
              option.append(label + " (" + count + ")");
              option.appendTo(select);
            }
        }
      });
      activateTypeAhead(genome, "ag", agList);
  }
};

const generateCellTypeOptions = async () => {
  const genome = genomeSelected();
  const agSelected = $("select#" + genome + "agClass option:selected").val();
  const clSelected = $("select#" + genome + "clClass option:selected").val();

  const select = $("select#" + genome + "clSubClass");
  select.empty();

  let response = await fetch(
    "/data/cell_type?genome=" +
      genome +
      "&clClass=" +
      clSelected +
      "&agClass=" +
      agSelected,
  );
  let clList = await response.json();

  clList.forEach((experiment, i) => {
    let id = experiment["id"];
    let label = experiment["label"];
    let count = experiment["count"];
    let option = $("<option>").attr("value", id);

    switch (agSelected) {
      case "Annotation tracks":
        label = "NA";
        option.append(label).attr("selected", true);
        option.appendTo(select);
        break;
      default:
        if (i == 0) {
          option.append(label).attr("selected", true);
          option.appendTo(select);
        } else {
          option.append(label + " (" + count + ")");
          option.appendTo(select);
        }
    }
  });
  activateTypeAhead(genome, "cl", clList);
};

// typeahead
const activateTypeAhead = (genome, panelType, listObject) => {
  const listLabels = listObject.map((experiment) => experiment.label);
  const typeaheadInput = $("#" + genome + panelType + "SubClass.typeahead");
  // destroy
  typeaheadInput.typeahead("destroy");
  // enable
  const list = new Bloodhound({
    datumTokenizer: Bloodhound.tokenizers.whitespace,
    queryTokenizer: Bloodhound.tokenizers.whitespace,
    local: listLabels,
  });
  typeaheadInput.typeahead(
    {
      hint: true,
      highlight: true,
      minLength: 1,
      limit: 10,
    },
    {
      name: "list",
      source: list,
    },
  );
  // sync
  typeaheadInput.on("typeahead:select keyup", function () {
    const input = $(this).val();
    if ($.inArray(input, listLabels) > -1) {
      $("select#" + genome + panelType + "SubClass").val(input);
    }
  });
};

/*
    Q-value options
*/

const generateQvalOptions = async () => {
  const genome = genomeSelected();

  const select = document.getElementById(genome + "qval");
  document
    .querySelectorAll("#" + genome + "qval option")
    .forEach((option) => option.remove());

  const agSelected = $("select#" + genome + "agClass option:selected").val();

  const opt = document.createElement("option");
  let val;
  switch (agSelected) {
    case "Bisulfite-Seq":
      opt.setAttribute("value", "bs");
      opt.setAttribute("selected", "true");

      val = document.createTextNode("NA");
      opt.appendChild(val);
      select.appendChild(opt);
      break;

    case "Annotation tracks":
      opt.setAttribute("value", "anno");
      opt.setAttribute("selected", "true");

      val = document.createTextNode("NA");
      opt.appendChild(val);
      select.appendChild(opt);
      break;

    default:
      let response = await fetch("/qvalue_range");
      let qvList = await response.json();
      qvList.forEach((qv, i) => {
        let opt = document.createElement("option");
        opt.setAttribute("value", qv);
        if (i == 0) opt.setAttribute("selected", "true");
        let val = document.createTextNode(parseInt(qv) * 10);
        opt.appendChild(val);
        select.appendChild(opt);
      });
  }
};

/*
    Genome Tab settings
*/

const genomeTabSettings = async () => {
  let response = await fetch("/data/list_of_genome.json");
  let genomeList = await response.json();
  genomeList.forEach((genome, i) => {
    changeSelect(genome);
    tabControl(genome);
    panelCollapse(genome);
    selectToHideAnother(genome);
  });
};

const changeSelect = (genome) => {
  const agSelectElement = document.querySelector("#" + genome + "agClass");
  agSelectElement.addEventListener("change", (event) => {
    generateSampleTypeOptions();
    generateChIPAntigenOptions();
    generateCellTypeOptions();
    generateQvalOptions();
  });

  const clSelectElement = document.querySelector("#" + genome + "clClass");
  clSelectElement.addEventListener("change", (event) => {
    generateChIPAntigenOptions();
    generateCellTypeOptions();
  });
};

const panelCollapse = (genome) => {
  $("#toggle-" + genome + "agSubClass").click(function () {
    $("#collapse-" + genome + "agSubClass").collapse("toggle");
  });
  $("#toggle-" + genome + "clSubClass").click(function () {
    $("#collapse-" + genome + "clSubClass").collapse("toggle");
  });
};

const selectToHideAnother = (genome) => {
  const twoSelectors = [
    "select#" + genome + "agSubClass",
    "select#" + genome + "clSubClass",
  ];
  $.each(twoSelectors, function (i, selector) {
    $(selector).on("typeahead:select keyup change", function () {
      if ($(twoSelectors[0]).val() != "-" && $(twoSelectors[1]).val() != "-") {
        disableAnother($(this), genome);
      }
    });
  });
};

const disableAnother = (thisSelector, genome) => {
  const span = $("<span>").attr("aria-hidden", "true").append("×");
  const button = $("<button>")
    .attr("type", "button")
    .attr("class", "close")
    .attr("data-dismiss", "alert")
    .attr("aria-label", "Close")
    .append(span);
  const message = $("<div>")
    .attr("class", "alert alert-warning alert-dismissible fade in")
    .attr("role", "alert")
    .append(button)
    .append('Either an "Antigen" or a "Cell type" is selectable.')
    .append("</div>");
  switch (thisSelector.attr("id").replace(genome, "").replace("SubClass", "")) {
    case "ag":
      $("select#" + genome + "clSubClass").val("-");
      if ($(".panel-message#" + genome + "agSubClass").is(":empty")) {
        $(".panel-message#" + genome + "agSubClass").append(message);
      }
      break;
    case "cl":
      $("select#" + genome + "agSubClass").val("-");
      if ($(".panel-message#" + genome + "clSubClass").is(":empty")) {
        $(".panel-message#" + genome + "clSubClass").append(message);
      }
      break;
  }
};

/*
    Set form
*/

const setForm = () => {
  sendBedToIGV();
  downloadBed();
};

const sendBedToIGV = () => {
  postFormData("button#submit", "/browse");
};

const downloadBed = () => {
  postFormData("button#download", "/download");
};

const postFormData = (buttonId, url) => {
  $(buttonId).on("click", function () {
    const button = $(this);
    // button off
    button.prop("disable", true);
    // get form data
    const genome = genomeSelected();
    const data = {
      condition: {
        genome: genome,
        agClass: $("select#" + genome + "agClass option:selected").val(),
        agSubClass: $("select#" + genome + "agSubClass option:selected").val(),
        clClass: $("select#" + genome + "clClass option:selected").val(),
        clSubClass: $("select#" + genome + "clSubClass option:selected").val(),
        qval: $("select#" + genome + "qval option:selected").val(),
      },
    };
    // post
    $.ajax({
      type: "POST",
      url: url,
      data: JSON.stringify(data),
      contentType: "application/json",
      dataType: "json",
      scriptCharset: "utf-8",
    })
      .done(function (response) {
        window.open(response.url, "_self", "");
      })
      .fail(function (response) {
        console.log(
          "Error: failed to send/get data. Please contact from github issue",
        );
      });
    // button on
    button.prop("disable", false);
  });
};

/*
    Show help messages
*/

const showHelp = () => {
  const helpText = {
    threshold:
      "Set the threshold for statistical significance values calculated by peak-caller MACS2 (-10*Log10[MACS2 Q-value]). If 50 is set here, peaks with Q value < 1E-05 are shown on genome browser IGV. Colors shown in IGV indicate the statistical significance values as follows: blue (50), cyan (250), green (500), yellow (750), and red (> 1,000).",
    viewOnIGV:
      'IGV must be running on your computer before clicking the button.\n\nIf your browser shows "cannot open the page" error, launch IGV and allow an access via port 60151 (from the menu bar of IGV, View > Preferences... > Advanced > "enable port" and set port number 60151) to browse the data.\n\nClick OK to go to the IGV website, or cancel to back to ChIP-Atlas.',
  };

  $(".infoBtn").click(function () {
    const genome = genomeSelected();
    switch ($(this).attr("id")) {
      case genome + "Threshold":
        alert(helpText["threshold"]);
        break;
      case genome + "ViewOnIGV":
        if (window.confirm(helpText["viewOnIGV"])) {
          window.open("https://igv.org/doc/desktop/#DownloadPage/", "_blank");
        }
        break;
    }
  });
};
