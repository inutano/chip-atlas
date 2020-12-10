// onload
$(function(){
  $('#Simple-tab a').click(function (e) {
    e.preventDefault()
    $(this).tab('show')
  });

  $('#Advanced-tab a').click(function (e) {
    e.preventDefault()
    $(this).tab('show')
  });

  jQuery.fn.dataTableExt.aTypes.unshift(
    function ( sData )
    {
      var sValidChars = "0123456789-,./";
      var Char;
      var bDecimal = false;
      for ( i=0 ; i<sData.length ; i++ ){
        Char = sData.charAt(i);
        if (sValidChars.indexOf(Char) == -1)
        {
          return null;
        }
        if ( Char == "," )
        {
          if ( bDecimal )
          {
            return null;
          }
          bDecimal = true;
        }
      }
      return 'numeric-comma';
    }
  );

  jQuery.fn.dataTableExt.oSort['numeric-comma-asc']  = function(a,b) {
    var x = (a == "-") ? 0 : a.replace( /,/, "" );
    var y = (b == "-") ? 0 : b.replace( /,/, "" );
    x = parseFloat( x );
    y = parseFloat( y );
      return ((x < y) ? -1 : ((x > y) ?  1 : 0));
  };

  jQuery.fn.dataTableExt.oSort['numeric-comma-desc'] = function(a,b) {
    var x = (a == "-") ? 0 : a.replace( /,/, "" );
    var y = (b == "-") ? 0 : b.replace( /,/, "" );
    x = parseFloat( x );
    y = parseFloat( y );
    return ((x < y) ?  1 : ((x > y) ? -1 : 0));
  };

  simpleSearch();
  advancedSearch();
});

function simpleSearch() {
  $('#SimpleSearchDataTable').DataTable({
    deferRender: true,
    dom: '<"top"fliB>tpr<"bottom"><"clear">',
    aLengthMenu: [[10, 20, 50, 100], [10, 20, 50, 100]],
    iDisplayLength: 10,
    buttons: [
      'copyHtml5',
      {
          text: 'TSV',
          extend: 'csvHtml5',
          fieldSeparator: '\t',
          extension: '.tsv'
      }
    ],
    ajax: "/data/ExperimentList.json",
    columns: [
        { title: "<a title='Experimental ID.'>SRX ID</a>",
          render: function ( data, type, row ) {
            return "<a title='Open this Info...' target='_blank' style='text-decoration: none' href='/view?id=" + data +  "'>" + data + "</a>";
          }
        },
        { title: "<a title='Accession ID'>SRA ID</a>" },
        { title: "<a title='Experimental ID in GEO'>GEO ID",
          render: function ( data, type, row ) {
            if (data != "-") {
              return "<a title='Open this Info...' target='_blank' style='text-decoration: none' href='https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=" + data +  "'>" + data + "</a>";
            } else {
              return data;
            }
          }
        },
        { title: "<a title='Genome assembly (hg19, mm9, rn6, dm3, ce10, sacCer3)'>Genome</a>" },
        { title: "<a title='Curated antigen class'>Antigen class</a>" },
        { title: "<a title='Curated antigen name'>Antigen</a>" },
        { title: "<a title='Curated cell type class'>Cell type class</a>" },
        { title: "<a title='Curated cell type'>Cell type</a>" }
    ],
    order: [[ 6, "asc" ]]
  });
}

function advancedSearch() {
    $('#AdvancedSearchDataTable').DataTable( {
        deferRender: true,
        dom: '<"top"fliB>tpr<"bottom"><"clear">',
        aLengthMenu: [[10, 20, 50, 100], [10, 20, 50, 100]],
        iDisplayLength: 10,
        buttons: [
            'copyHtml5',
            {
                text: 'TSV',
                extend: 'csvHtml5',
                fieldSeparator: '\t',
                extension: '.tsv'
            }
        ],
        ajax: "/data/ExperimentList_adv.json",
        columns: [
            { title: "<a title='Experimental ID.'>SRX ID</a>",
              render: function ( data, type, row ) {
                return "<a title='Open this Info...' target='_blank' style='text-decoration: none' href='/view?id=" + data +  "'>" + data + "</a>";
              }
            },
            { title: "<a title='Accession ID'>SRA ID</a>" },
            { title: "<a title='Experimental ID in GEO'>GEO ID",
              render: function ( data, type, row ) {
                if (data != "-") {
                  return "<a title='Open this Info...' target='_blank' style='text-decoration: none' href='https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=" + data +  "'>" + data + "</a>";
                } else {
                  return data;
                }
              }
            },
            { title: "<a title='Genome assembly (hg19, mm9, rn6, dm3, ce10, sacCer3)'>Genome</a>" },
            { title: "<a title='Curated antigen class'>Antigen class</a>" },
            { title: "<a title='Curated antigen name'>Antigen</a>" },
            { title: "<a title='Curated cell type class'>Cell type class</a>" },
            { title: "<a title='Curated cell type'>Cell type</a>" },
            { title: "<a title='Title written by authors'>Title</a>" },
            { title: "<a title='Attributes written by authors'>Attributes</a>",
              render: function ( data, type, row ) {
                if (data != "-") {
                  data = '<b>' + data;
                  data = data.replace( /=/g, '</b>: ' );
                  data = data.replace( /__TAB__/g, '<br><b>' );
                  return data;
                } else {
                  return data;
                }
              }
            }
        ],
        order: [[ 6, "asc" ]]
    } );
}
