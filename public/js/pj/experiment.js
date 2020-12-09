// onload
$(function(){
  dbLinkOut();
  analysisLinkOut();
  showHelp();
  //browseIgv();
  loadImages();
})

// variables
var dbNamespace = {
  wikigenes: "https://www.wikigenes.org/?search=",
  posmed: "http://omicspace.riken.jp/PosMed/search?actionType=searchexec&keyword=",
  pdbj: "http://pdbj.org/mine/search?query=",
  atcc: "http://www.atcc.org/Search_Results.aspx?searchTerms=",
  mesh: "https://www.ncbi.nlm.nih.gov/mesh/?term=",
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

function analysisLinkOut(){
  var expid = getUrlParameter('id');
  $.ajax({
    type: 'GET',
    url: '/data/exp_metadata.json?expid=' + expid,
    dataType: 'json'
  }).done(function(records){
    $.each(records, function(i, record){
      var genome = record['genome'];
      var dbarc = "http://dbarchive.biosciencedbc.jp/kyushu-u/" + genome;
      var urlList = [
        ["Colocalization", dbarc + "/colo/" + expid + ".html"],
        ["Target Genes (TSS ± 1kb)", dbarc + "/target/" + expid + ".1.html"],
        ["Target Genes (TSS ± 5kb)", dbarc + "/target/" + expid + ".5.html"],
        ["Target Genes (TSS ± 10kb)", dbarc + "/target/" + expid + ".10.html"]
      ];

      $.each(urlList, function(i, kv){
        var text = kv[0];
        var url = kv[1];
        $.ajax({
          type: 'GET',
          url: "/api/remoteUrlStatus?url=" + url,
          complete: function(transport){
            if(transport.status == 200){
              $('ul#analysisLinkOut.' + genome).append("<li><a href='" + url + "'>" + text + "</a></li>");
            }
            if (i == urlList.length-1){
              if ($('ul#analysisLinkOut.' + genome).children().length == 0) {
                $('ul#analysisLinkOut.' + genome).append("<li class='dropdown-header'>No data available for this record</li>");
              }
            }
          }
        });
      });
    });
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
    var url = getLinkOutUrl(link, expid, metadata);
    window.open(url, "_self", "")
    // var igvUrl = 'http://127.0.0.1:60151';
    // $.ajax({
    //   type: 'GET',
    //   url: igvUrl
    // }).done(function(response){
    //   var url = getLinkOutUrl(link, expid, metadata);
    //   window.open(url, "_self", "")
    // }).fail(function(response){
    //     alert("IGV is not running on your computer.\n\nLaunch IGV and allow an access via port 60151 (View > Preferences... > Advanced > check 'enable port' and set port number 60151) to browse data.\n\n If you have not installed IGV, visit  https://www.broadinstitute.org/igv/download or google 'Integrative Genomics Viewer' to download the software.");
    // })
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

// Loading fastqc images
function loadImages(){
  startLoading();
  var expid = getUrlParameter('id');
  $.ajax({
    url: "/data/fastqc_images.json?expid=" + expid,
    type: 'GET',
    dataType: 'json',
  }).done(function(json){
    var images_url = json;
    putImages(images_url);
    removeLoading();
  });
}

function putImages(images_url){
  var target = $(".sequence_quality")
  $.each(images_url, function(i, url){
    var image = $("<img>").attr("src",url).attr("width",350)
    var alink = $("<a>").attr("href",url).append(image).append("</a>")
    var title = url.split("/")[9];
    var head = $("<h4>").append(title).append("</h4>");
    $("<div>")
      .attr("class", "col-md-3")
      .append(head)
      .append(alink)
      .append("</div>")
      .appendTo(target)
  });
}

function startLoading(){
  var target = $(".sequence_quality");
  $("<p>")
    .attr("id","loadingImages")
    .append("loading images..")
    .append("</p>")
    .appendTo(target);
}

function removeLoading(){
  $("#loadingImages").remove();
}

function showHelp(){
  $('.infoBtn').click(function(){
    switch($(this).attr('id')){
      case 'viewOnIGV':
        alert(helpText["viewOnIGV"]);
        break;
    };
  });
}

var helpText = {
  threshold: 'Set the threshold for statistical significance values calculated by peak-caller MACS2 (-10*Log10[MACS2 Q-value]). If 50 is set here, peaks with Q value < 1E-05 are shown on genome browser IGV.',
  viewOnIGV: 'IGV must be running on your computer before clicking the button.\n\nIf your browser shows "cannot open the page" error, launch IGV and allow an access via port 60151 (from the menu bar of IGV, View > Preferences... > Advanced > "enable port" and set port number 60151) to browse the data. If you have not installed IGV on your computer, visit https://www.broadinstitute.org/igv/download or google "Integrative Genomics Viewer" to download the software.'
};
