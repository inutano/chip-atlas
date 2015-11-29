// global variables
var analysis;

// onload
$(function(){
  // tab trigger event
  tabTriggerEvents();

  // retrieve hash
  $.ajax({
    type: 'GET',
    url: '/data/colo_analysis.json',
    dataType: 'json',
    success: function(json){
      analysis = json;
      var genome = genomeSelected();
      $("input#"+genome+"dataTypeAntigen").attr("checked","checked");
      setPanel('PrimaryPanel', analysis);
      setPanel('SecondaryPanel', analysis);

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

          // change primary type radio button
          $.each(["Antigen","CellType"], function(i, type){
            $('input[name="'+genome+'datatypeoption"]:radio').change(function(){
              setPanel('PrimaryPanel', analysis);
              setPanel('SecondaryPanel', analysis);
            })
          });

          // generate secondary options
          $('select#' + genome + 'PrimaryPanel-select').change(function(){
            setPanel('SecondaryPanel', analysis)
          });
        })
      });
    }
  });
});

// functions
function setPanel(panel, analysis){
  changePanelTitle();
  removeCurrentOptions(panel);
  var options = getOptions(panel, analysis);
  appendOptions(panel, options);
  enableTypeAhead(panel, options);
}

function changePanelTitle(){
  var genome = genomeSelected();
  var type = $(':radio[name="'+genome+'datatypeoption"]:checked').val();
  // change panel title
  if(type == "antigen"){
    $('#' + genome + 'PrimaryPanel h4').text("2. Choose Antigen");
    $('#' + genome + 'SecondaryPanel h4').text("3. Choose Cell Type Class");
  }else{
    $('#' + genome + 'PrimaryPanel h4').text("2. Choose Cell Type Class");
    $('#' + genome + 'SecondaryPanel h4').text("3. Choose Antigen");
  }
}

function removeCurrentOptions(panel){
  // panel = 'PrimaryPanel' or 'SecondaryPanel'
  var genome = genomeSelected();
  var target = $('select#' + genome + panel + '-select');
  target.empty();
}

function getOptions(panel, analysis){
  var genome = genomeSelected();
  var type = $(':radio[name="'+genome+'datatypeoption"]:checked').val();
  var options;
  switch(panel){
    case 'PrimaryPanel':
      options = $.map(analysis[genome][type], function(value, key){
        return key;
      });
      break;
    case 'SecondaryPanel':
      var primaryType = $('select#' + genome + 'PrimaryPanel-select').val();
      options = analysis[genome][type][primaryType];
      break;
  }
  return options;
}

function appendOptions(panel, options){
  var genome = genomeSelected();
  var targetSelect = $('select#' + genome + panel + '-select');
  targetSelect.empty();
  options.sort().forEach(function(element, index, array){
    if(index==0){
      $('<option>')
        .attr("value", element)
        .attr("selected","selected")
        .append(element)
        .appendTo(targetSelect);
    }else{
      $('<option>')
        .attr("value", element)
        .append(element)
        .appendTo(targetSelect);
    };
  });
}

function enableTypeAhead(panel, options){
  var genome = genomeSelected();
  var typeaheadInput = $('#' + genome + panel + '-typeahead');
  typeaheadInput.typeahead('destroy');  // Erase previous data set
  var list = new Bloodhound({ // create list for incremental search
    datumTokenizer: Bloodhound.tokenizers.whitespace,
    queryTokenizer: Bloodhound.tokenizers.whitespace,
    local: options
  });
  typeaheadInput.typeahead({ // activate typeahead
    hint: true,
    highlight: true,
    minLength: 1
  },{
    name: 'list',
    source: list
  });
  // sync textbox and input field
  typeaheadInput.on('typeahead:select keyup', function(){
    var input = $(this).val();
    if($.inArray(input,options) > -1){
      $('select#' + genome + panel + '-select').val(input);
    }
    if($(this).attr("id") === genome + "PrimaryPanel-typeahead"){
      setPanel('SecondaryPanel', analysis);
    }
  });
}

// send data to view/download data
$(function(){
  $("button.post").click(function(){
    var button = $(this);
    button.attr("disabled", true);

    var buttonId = $(this).attr("id");
    var suffix;
    switch(buttonId){
      case 'colo-submit':
        suffix = 'submit';
        break;
      case 'download-tsv':
        suffix = 'tsv';
        break;
      case 'download-gml':
        suffix = 'gml';
        break;
    };

    $.ajax({
      type : 'post',
      url : "/colo?type="+suffix,
      data: JSON.stringify(retrievePostData()),
      contentType: 'application/json',
      dataType: 'json',
      scriptCharset: 'utf-8',
      success : function(response) {
        // alert(JSON.stringify(response));
        window.open(response.url, "_self", "")
      },
      error : function(response){
        // alert(JSON.stringify(response));
        alert("error!");
        window.open("/not_found", "_self", "")
      },
      complete: function(){
        button.attr("disabled", false);
      }
    });
  })
})

function retrievePostData(){
  var genome = $('.genomeTab ul li.active a').attr('source').replace(/[\n\s ]/g, "");
  var primaryType = $(':radio[name="'+genome+'datatypeoption"]:checked').val();
  var primaryValue = $('select#' + genome + 'PrimaryPanel-select').val();
  var secondaryValue = $('select#' + genome + 'SecondaryPanel-select').val();
  var data;
  switch(primaryType){
    case 'antigen':
      data = {
        condition: {
          genome: genome,
          antigen: primaryValue,
          cellline: secondaryValue
        }
      };
      break;
    case 'cellline':
      data = {
        condition: {
          genome: genome,
          antigen: secondaryValue,
          cellline: primaryValue
        }
      };
      break;
  }
  return data;
}
