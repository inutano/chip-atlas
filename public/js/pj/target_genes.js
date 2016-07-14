// global variables
var analysis;
var listOfGenome;

// onload
$(function(){
  // retrieve analysis hash
  $.ajax({
    type: 'GET',
    url: '/data/target_genes_analysis.json',
    dataType: 'json',
    success: function(analysisJson){
      analysis = analysisJson;
      setPanel('AntigenPanel', analysis);
      // retrieve list of genomes
      $.ajax({
        type: 'GET',
        url: '/data/list_of_genome.json',
        dataType: 'json',
        success: function(genomeJson){
          listOfGenome = genomeJson;
          $.each(genomeJson, function(i, genome){
            // activate typeahead
            var options = analysisJson[genome];
            enableTypeAhead('AntigenPanel', options, genome)
            // set tab controller
            $('#' + genome + '-tab a').click(function(e){
              e.preventDefault();
              $(this).tab('show');
              setPanel('AntigenPanel', analysisJson);
            })
          })
        }
      });
    }
  });

  // click button to submit data and browse data
  $("button.post").click(function(){
    var button = $(this);
    button.attr("disabled", true);

    var buttonId = $(this).attr("id");
    var suffix;
    switch(buttonId){
      case 'target-gene-submit':
        suffix = 'submit';
        break;
      case 'target-gene-download':
        suffix = 'tsv';
        break;
    };

    $.ajax({
      type : 'post',
      url : "/target_genes?type="+suffix,
      data: JSON.stringify(retrievePostData()),
      contentType: 'application/json',
      dataType: 'json',
      scriptCharset: 'utf-8',
      success : function(response) {
        // alert(JSON.stringify(response));
        var url = response.url
        $.ajax({
          url: "/api/remoteUrlStatus?url="+url,
          type: 'GET',
          complete: function(transport){
            console.log(transport.status);
            if(transport.status == 200){
              window.open(url, "_self", "");
            }else{
              alert("No data found:\n\nTarget gene analysis data is not available with this condition. Please change the distance from TSS or select another antigen.");
            }
          }
        });
      },
      error : function(response){
        // alert(JSON.stringify(response));
        alert("error!");
      },
      complete: function(){
        button.attr("disabled", false);
      }
    });
  })
});

// functions
function setPanel(panel, analysis){
  removeCurrentOptions(panel);
  var options = getOptions(panel, analysis);
  appendOptions(panel, options);
  enableTypeAhead(panel, options);
}

function removeCurrentOptions(panel){
  // panel = 'PrimaryPanel' or 'SecondaryPanel'
  var genome = genomeSelected();
  var target = $('select#' + genome + panel + '-select');
  target.empty();
}

function getOptions(panel, analysis){
  var genome = genomeSelected();
  return analysis[genome];
}

function appendOptions(panel, options){
  var genome = genomeSelected();
  var targetSelect = $('select#' + genome + panel + '-select');
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

function enableTypeAhead(panel, options, genome){
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
  });
}

function retrievePostData(){
  var genome = $('.genomeTab ul li.active a').attr('source').replace(/[\n\s ]/g, "");
  var data = {
    // igv: $().text
    condition: {
      genome: genome,
      antigen: $('select#' + genome + 'AntigenPanel-select option:selected').val(),
      distance: $('input[name='+genome+'DistanceOption]:checked').val()
    }
  };
  return data;
}
