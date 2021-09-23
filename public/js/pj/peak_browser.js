// onload
$(function(){
  // tab trigger event
  peakBrowserTabTriggerEvents();

  // iterate for each genome
  var genomeList;
  $.ajax({
    type: 'GET',
    url: '/data/list_of_genome.json',
    dataType: 'json',
  }).done(function(json){
    genomeList = json;
    $.each(genomeList, function(i, genome){
      tabControl(genome);
      panelCollapse(genome);
      selectToHideAnother(genome);
    })
  });

  // help message
  showHelp();

  // post form data
  sendBedToIGV();
  downloadBed();

  // Append initial subclass options
  generateSubClassOptions();
  // generate sub class options by selecting class name
  setSubClassOptions();
})

// functions
function peakBrowserTabTriggerEvents(){
  $('a[data-toggle="tab"]').on('shown.bs.tab', function(e){
    var activatedTab = e.target;
    var previousTab = e.relatedTarget;
    resetSubClassOptions();
  });
}

function panelCollapse(genome){
  $.each(["ag", "cl"], function(i, type){
    $('#toggle-' + genome + type + 'SubClass').click(function(){
      $('#collapse-' + genome + type + 'SubClass').collapse('toggle');
    });
  });
}

// sub class options
function setSubClassOptions(){
  $('select.classSelect').change(function(){
    resetSubClassOptions();
    generateSubClassOptions();
  });
}

function resetSubClassOptions(){ // Erase existing options and put an option for 'all'
  var genome = genomeSelected();
  $.each(['ag', 'cl'], function(i, t){
    var subClassSelect = $('select#' + genome + t + 'SubClass');
    subClassSelect.empty();
    $("<option>")
      .attr("value", "-")
      .attr("selected", "true")
      .append("All")
      .appendTo(subClassSelect);
  });
}

function generateSubClassOptions(){
  var genome = genomeSelected();
  var agSelected = $('select#' + genome + 'agClass option:selected').val();
  var clSelected = $('select#' + genome + 'clClass option:selected').val();
  $.each([['ag', agSelected], ['cl', clSelected]], function(i, set){
    var url = '/data/index_subclass.json?' + 'genome=' + genome + '&agClass=' + agSelected + '&clClass=' + clSelected + '&type=' + set[0];
    $.ajax({
      type: 'GET',
      url: url,
      dataType: 'json'
    }).done(function(json){
      var options = json;
      putSubClassOptions(options, 'select#' + genome + set[0] + 'SubClass')
      activateTypeAhead(genome, set[0], options);
    });
  });
}

function putSubClassOptions(options, panelAppendTo){
  $.map(options, function(value, key){
    return [[key, value]];
  }).sort().forEach(function(element,index,array){
    var name = element[0];
    var count = element[1];
    appendSubClassOption(name, count, panelAppendTo);
  });
}

function appendSubClassOption(name, count, panelAppendTo){
  $('<option>')
    .attr("value", name)
    .append(name + " (" + count + ")")
    .appendTo(panelAppendTo);
}

// typeahead
function activateTypeAhead(genome, panelType, options){
  var listSubClass = $.map(options, function(value, key){
    return key;
  });
  var typeaheadInput = $('#' + genome + panelType + 'SubClass.typeahead');
  removePreviousTypeahead(typeaheadInput);
  enableTypeAhead(listSubClass, typeaheadInput);
  syncTypeaheadAndInput(listSubClass, typeaheadInput, panelType);
}

function removePreviousTypeahead(typeaheadInput){
  typeaheadInput.typeahead('destroy');
}

function enableTypeAhead(listSubClass, typeaheadInput){
  var list = new Bloodhound({
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
}

function syncTypeaheadAndInput(listSubClass, typeaheadInput, type){
  var genome = genomeSelected();
  typeaheadInput.on('typeahead:select keyup', function(){
    var input = $(this).val();
    if($.inArray(input,listSubClass) > -1){
      $('select#' + genome + type + 'SubClass').val(input);
    }
  });
}

function selectToHideAnother(genome){
  var twoSelectors = ['select#' + genome + 'agSubClass', 'select#' + genome + 'clSubClass'];
  $.each(twoSelectors, function(i, selector){
    $(selector).on('typeahead:select keyup change', function(){
      if($(twoSelectors[0]).val() != "-" && $(twoSelectors[1]).val() != "-"){
        disableAnother($(this), genome);
      };
    })
  });
}

function disableAnother(thisSelector, genome){
  var span = $('<span>')
        .attr("aria-hidden","true")
        .append("×");
  var button = $('<button>')
        .attr("type","button")
        .attr("class","close")
        .attr("data-dismiss","alert")
        .attr("aria-label","Close")
        .append(span);
  var message = $('<div>')
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

function sendBedToIGV(){
  postFormData('button#submit', '/browse');
}

function downloadBed(){
  postFormData('button#download', '/download')
}

function postFormData(buttonId, url){
  $(buttonId).on('click', function(){
    var button = $(this);
    button.prop("disable", true);
    if(url == '/browse'){
      postDataAjax(url);
      // var igvUrl = 'http://127.0.0.1:60151';
      // $.ajax({
      //   url: igvUrl,
      //   type: 'GET'
      // }).done(function(response){
      //   postDataAjax(url);
      // }).fail(function(response){
      //   alert("IGV is not running on your computer.\n\nLaunch IGV and allow an access via port 60151 (View > Preferences... > Advanced > check 'enable port' and set port number 60151) to browse data.\n\n If you have not installed IGV, visit  https://www.broadinstitute.org/igv/download or google 'Integrative Genomics Viewer' to download the software.");
      // })
    }else{
      postDataAjax(url);
    }
    button.prop("disable", false);
  });
}

function postDataAjax(url){
  var data = getFormData();
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
}

function getFormData(){
  var genome = genomeSelected();
  var data = {
    // igv: $().text
    condition: {
      genome: genome,
      agClass: $('select#' + genome + 'agClass option:selected').val(),
      agSubClass: $('select#' + genome + 'agSubClass option:selected').val(),
      clClass: $('select#' + genome + 'clClass option:selected').val(),
      clSubClass: $('select#' + genome + 'clSubClass option:selected').val(),
      qval: $('select#' + genome + 'qval option:selected').val()
    }
  };
  return data
}

function showHelp(){
  $('.infoBtn').click(function(){
    var genome = genomeSelected();
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

var helpText = {
  threshold: 'Set the threshold for statistical significance values calculated by peak-caller MACS2 (-10*Log10[MACS2 Q-value]). If 50 is set here, peaks with Q value < 1E-05 are shown on genome browser IGV. Colors shown in IGV indicate the statistical significance values as follows: blue (50), cyan (250), green (500), yellow (750), and red (> 1,000).',
  viewOnIGV: 'IGV must be running on your computer before clicking the button.\n\nIf your browser shows "cannot open the page" error, launch IGV and allow an access via port 60151 (from the menu bar of IGV, View > Preferences... > Advanced > "enable port" and set port number 60151) to browse the data. If you have not installed IGV on your computer, visit https://www.broadinstitute.org/igv/download or google "Integrative Genomics Viewer" to download the software.'
};
