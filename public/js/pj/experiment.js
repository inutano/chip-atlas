// onload
$(function(){
  dbLinkOut();
  browseIgv();
})

// variables
var dbNamespace = {
  wikigenes: "https://www.wikigenes.org/?search=",
  posmed: "http://omicspace.riken.jp/PosMed/search?actionType=searchexec&keyword=",
  pdbj: "http://pdbj.org/mine/search?query=",
  atcc: "http://www.atcc.org/Search_Results.aspx?searchTerms=",
  mesh: "http://www.ncbi.nlm.nih.gov/mesh/?term=",
  rikenbrc: "http://www2.brc.riken.jp/lab/cell/list.cgi?skey="
};

var getUrlParameter = function getUrlParameter(sParam) {
  var sPageURL = decodeURIComponent(window.location.search.substring(1)),
    sURLVariables = sPageURL.split('&'),
    sParameterName,
    i;

  for (i = 0; i < sURLVariables.length; i++) {
    sParameterName = sURLVariables[i].split('=');
    if (sParameterName[0] === sParam) {
      return sParameterName[1] === undefined ? true : sParameterName[1];
    }
  }
};

// functions
function dbLinkOut(){
  $('button').on('click', function(event){
    event.preventDefault();
    var namespace = dbNamespace[$(this).attr("id")];
    switch (true){
      case $(this).hasClass('antigen'):
        var id = $('input#queryAntigen').val().replace(/\s/,"+");
        var uri = namespace + id;
        break;
      case $(this).hasClass('celltype'):
        var id = $('input#queryCelltype').val().replace(/\s/,"+");
        var uri = namespace + id;
        break;
    };
    window.open(uri);
  });
}

function browseIgv(){
  var expid = getUrlParameter('id');
  // retrieve metadata
  $.ajax({
    type: 'GET',
    url: '/data/exp_metadata.json?expid=' + expid,
    dataType: 'json'
  }).done(function(json){
    var metadata = json;
    openIgvUri(expid, metadata);
  })
}

function openIgvUri(expid, metadata){
  var params = getUrlParameters(expid, metadata);
  $("a.link-igv").on('click', function(){
    var link = $(this);
    // check if igv is running
    var igvUrl = 'http://127.0.0.1:60151';
    $.ajax({
      type: 'GET',
      url: igvUrl
    }).done(function(response){
      var url = getLinkOutUrl(link, expid, metadata);
      window.open(url, "_self", "")
    }).fail(function(response){
        alert("IGV is not running on your computer.\n\nLaunch IGV and allow an access via port 60151 (View > Preferences... > Advanced > check 'enable port' and set port number 60151) to browse data.\n\n If you have not installed IGV, visit  https://www.broadinstitute.org/igv/download or google 'Integrative Genomics Viewer' to download the software.");
    })
  });
}

function getLinkOutUrl(link, expid, metadata){
  var dType = link.attr("name");
  var params = getUrlParameters(expid, metadata);
  var genome = params['genome']
  var url;
  switch(dType){
    case "bigwig":
      url = params['baseUrl']+'/bw/'+expid+'.bw&genome='+genome+'&name='+params['fname']
      break;
    case "bed":
      var dValue = link.attr("value");
      url = params['baseUrl']+'/bb'+dValue+'/'+expid+'.'+dValue+'.bb&genome='+genome+'&name='+params['fname']+'%20(1E-'+dValue+')';
      break;
  }
  return url;
}

function getUrlParameters(expid, metadata){
  var genome = metadata['genome'];
  var antigen = metadata["agSubClass"];
  var celltype = metadata["clSubClass"];
  var antigenEnc = encodeURI(antigen);
  var celltypeEnc = encodeURI(celltype);
  var igvUrl = 'http://localhost:60151/load?file=';
  var nbdcUrl = 'http://dbarchive.biosciencedbc.jp/kyushu-u';
  var params = {
    baseUrl: igvUrl+nbdcUrl+"/"+genome+'/eachData',
    genome: genome,
    antigen: antigenEnc,
    celltype: celltypeEnc,
    fname: encodeURI(antigen+' (@ '+celltype+') '+expid),
    dfname: genome+'_'+antigenEnc+'_'+celltypeEnc+'_'+expid
  }
  return params
}
