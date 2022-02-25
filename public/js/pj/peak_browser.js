window.onload = () => {
  initOptions();
  peakBrowserTabTriggerEvents();
  genomeTabSettings();
  setForm();
  showHelp();
};

const initOptions = () => {
  generateSubClassOptions();
  generateQvalOptions();
  $('select.classSelect').change(function(){
    generateSubClassOptions();
    generateQvalOptions();
  });
}

const peakBrowserTabTriggerEvents = () => {
  $('a[data-toggle="tab"]').on('shown.bs.tab', function(e){
    const activatedTab = e.target;
    const previousTab = e.relatedTarget;
    initOptions();
  });
}

/*
     Antigen/Cell type SubClass option generation
*/

const generateSubClassOptions = () => {
  const genome = genomeSelected();
  $('select#' + genome + 'agSubClass').empty();
  $('select#' + genome + 'clSubClass').empty();

  const agSelected = $('select#' + genome + 'agClass option:selected').val();
  const clSelected = $('select#' + genome + 'clClass option:selected').val();
  addAgSubClassOptions(genome, agSelected, clSelected)
  addClSubClassOptions(genome, agSelected, clSelected)
}

const addAgSubClassOptions = (genome, agSelected, clSelected) => {
  var url = '/data/index_subclass.json?' + 'genome=' + genome + '&agClass=' + agSelected + '&clClass=' + clSelected + '&type=ag';
  const panelAppendTo = 'select#' + genome + 'agSubClass';
  switch (agSelected) {
    case 'Input control':
    case 'ATAC-Seq':
    case 'DNase-seq':
    case 'Bisulfite-Seq':
      // put 'NA'
      $('<option>')
        .attr("value", "-")
        .attr("selected", true)
        .append("NA")
        .appendTo(panelAppendTo);
      break;
    default:
      $.ajax({
        type: 'GET',
        url: url,
        dataType: 'json'
      }).done(function(json){
        const options = json;
        putSubClassOptions(options, panelAppendTo)
        activateTypeAhead(genome, 'ag', options);
      });
  }
}

const addClSubClassOptions = (genome, agSelected, clSelected) => {
  const url = '/data/index_subclass.json?' + 'genome=' + genome + '&agClass=' + agSelected + '&clClass=' + clSelected + '&type=cl';
  $.ajax({
    type: 'GET',
    url: url,
    dataType: 'json'
  }).done(function(json){
    const options = json;
    putSubClassOptions(options, 'select#' + genome + 'clSubClass')
    activateTypeAhead(genome, 'cl', options);
  });
}

const putSubClassOptions = (options, panelAppendTo) => {
  // put 'All'
  $('<option>')
    .attr("value", "-")
    .attr("selected", true)
    .append("All")
    .appendTo(panelAppendTo);

  $.map(options, function(value, key){
    return [[key, value]];
  }).sort().forEach(function(element,index,array){
    const name = element[0];
    const count = element[1];
    $('<option>')
      .attr("value", name)
      .append(name + " (" + count + ")")
      .appendTo(panelAppendTo);
  });
}

// typeahead
const activateTypeAhead = (genome, panelType, options) => {
  const listSubClass = $.map(options, function(value, key){
    return key;
  });
  const typeaheadInput = $('#' + genome + panelType + 'SubClass.typeahead');
  // destroy
  typeaheadInput.typeahead('destroy');
  // enable
  const list = new Bloodhound({
    datumTokenizer: Bloodhound.tokenizers.whitespace,
    queryTokenizer: Bloodhound.tokenizers.whitespace,
    local: listSubClass
  });
  typeaheadInput.typeahead({
    hint: true,
    highlight: true,
    minLength: 1
  },{
    name: 'list',
    source: list
  });
  // sync
  typeaheadInput.on('typeahead:select keyup', function(){
    const input = $(this).val();
    if($.inArray(input,listSubClass) > -1){
      $('select#' + genome + type + 'SubClass').val(input);
    }
  });
}

/*
    Q-value options
*/

const generateQvalOptions = () => {
  const genome = genomeSelected();
  $('select#' + genome + 'qval').empty(); // reset
  const agSelected = $('select#' + genome + 'agClass option:selected').val();
  const target = $('select#' + genome + 'qval');
  switch (agSelected) {
    case 'Bisulfite-Seq':
      $('<option>')
        .attr("value", 'bs')
        .append('NA')
        .attr("selected", true)
        .appendTo(target);
      break;
    default:
      $.ajax({
        type: 'GET',
        url: '/qvalue_range',
        dataType: 'json'
      }).done(function(json){
        $.each(json, function(i, qv){
          const opt = $('<option>')
            .attr("value", qv)
            .append(parseInt(qv) * 10)
          if (i == 0) {
            opt.attr("selected", true)
          }
          opt.appendTo(target);
        });
      });
  }
}

/*
    Genome Tab settings
*/

const genomeTabSettings = async () => {
  let response = await fetch('/data/list_of_genome.json');
  let genomeList = await response.json();
  genomeList.forEach((genome, i) => {
    tabControl(genome);
    panelCollapse(genome);
    selectToHideAnother(genome);
  });
}

const panelCollapse = (genome) => {
  $('#toggle-' + genome + 'agSubClass').click(function(){
    $('#collapse-' + genome + 'agSubClass').collapse('toggle');
  });
  $('#toggle-' + genome + 'clSubClass').click(function(){
    $('#collapse-' + genome + 'clSubClass').collapse('toggle');
  });
}

const selectToHideAnother = (genome) => {
  const twoSelectors = ['select#' + genome + 'agSubClass', 'select#' + genome + 'clSubClass'];
  $.each(twoSelectors, function(i, selector){
    $(selector).on('typeahead:select keyup change', function(){
      if($(twoSelectors[0]).val() != "-" && $(twoSelectors[1]).val() != "-"){
        disableAnother($(this), genome);
      };
    })
  });
}

const disableAnother = (thisSelector, genome) => {
  const span = $('<span>')
        .attr("aria-hidden","true")
        .append("×");
  const button = $('<button>')
        .attr("type","button")
        .attr("class","close")
        .attr("data-dismiss","alert")
        .attr("aria-label","Close")
        .append(span);
  const message = $('<div>')
        .attr("class","alert alert-warning alert-dismissible fade in")
        .attr("role","alert")
        .append(button)
        .append('Either an "Antigen" or a "Cell type" is selectable.')
        .append('</div>');
  switch(thisSelector.attr("id").replace(genome,"").replace("SubClass","")){
    case "ag":
      $('select#' + genome + 'clSubClass').val("-");
      if($('.panel-message#' + genome + 'agSubClass').is(':empty')){
        $('.panel-message#' + genome + 'agSubClass').append(message);
      }
      break;
    case "cl":
      $('select#' + genome + 'agSubClass').val("-");
      if($('.panel-message#' + genome + 'clSubClass').is(':empty')){
        $('.panel-message#' + genome + 'clSubClass').append(message);
      }
      break;
  };
};

/*
    Set form
*/

const setForm = () => {
  sendBedToIGV();
  downloadBed();
}

const sendBedToIGV = () => {
  postFormData('button#submit', '/browse');
}

const downloadBed = () => {
  postFormData('button#download', '/download')
}

const postFormData = (buttonId, url) => {
  $(buttonId).on('click', function(){
    const button = $(this);
    // button off
    button.prop("disable", true);
    // get form data
    const genome = genomeSelected();
    const data = {
      condition: {
        genome: genome,
        agClass: $('select#' + genome + 'agClass option:selected').val(),
        agSubClass: $('select#' + genome + 'agSubClass option:selected').val(),
        clClass: $('select#' + genome + 'clClass option:selected').val(),
        clSubClass: $('select#' + genome + 'clSubClass option:selected').val(),
        qval: $('select#' + genome + 'qval option:selected').val()
      }
    };
    // post
    $.ajax({
      type: 'POST',
      url: url,
      data: JSON.stringify(data),
      contentType: 'application/json',
      dataType: 'json',
      scriptCharset: 'utf-8'
    }).done(function(response){
      window.open(response.url, "_self", "")
    }).fail(function(response){
      console.log("Error: failed to send/get data. Please contact from github issue");
    });
    // button on
    button.prop("disable", false);
  });
}

/*
    Show help messages
*/

const showHelp = () => {
  const helpText = {
    threshold: 'Set the threshold for statistical significance values calculated by peak-caller MACS2 (-10*Log10[MACS2 Q-value]). If 50 is set here, peaks with Q value < 1E-05 are shown on genome browser IGV. Colors shown in IGV indicate the statistical significance values as follows: blue (50), cyan (250), green (500), yellow (750), and red (> 1,000).',
    viewOnIGV: 'IGV must be running on your computer before clicking the button.\n\nIf your browser shows "cannot open the page" error, launch IGV and allow an access via port 60151 (from the menu bar of IGV, View > Preferences... > Advanced > "enable port" and set port number 60151) to browse the data. If you have not installed IGV on your computer, visit https://www.broadinstitute.org/igv/download or google "Integrative Genomics Viewer" to download the software.'
  };

  $('.infoBtn').click(function(){
    const genome = genomeSelected();
    switch($(this).attr('id')){
      case genome + 'Threshold':
        alert(helpText["threshold"]);
        break;
      case genome + 'ViewOnIGV':
        alert(helpText["viewOnIGV"]);
        break;
    };
  });
}
