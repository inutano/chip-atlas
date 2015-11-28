// onload
$(function(){
  // experiment search button
  enableExperimentSearch();
});

// common functions

function enableExperimentSearch(){
  $('button.go-experiment').on('click', function(event){
    event.preventDefault();
    var expid = $('input#jumpToExperiment').val();
    window.open('/view?id='+expid);
  });
}

function genomeSelected(){
  return $('.genomeTab ul li.active a').attr("source").replace(/[\n\s ]/g, "");
}

function tabTriggerEvents(){
  $('a[data-toggle="tab"]').on('shown.bs.tab', function(e){
    var activatedTab = e.target;
    var previousTab = e.relatedTarget;
    resetSubClassOptions();
  });
}

function tabControl(genome){
  $('#' + genome + '-tab a').click(function(e){
    e.preventDefault();
    $(this).tab('show')
  })
}
