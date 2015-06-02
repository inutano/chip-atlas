// retrieve index
$.getJSON(window.location.origin + '/data/index_all_genome', function(result){
	var indexAll = JSON.parse();
	var list_of_genome = indexAll.keys;
});

// iterate for each genomes
$.each(list_of_genome, function(i, genome){
	// set tab controller
	$('#' + genome + ' a').click(function(e){
		e.preventDefault();
		$(this).tab('show')
	})

	// collapse controller
	$.each(["ag", "cl"], function(i, type){
		$('#toggle-' + genome + type + 'SubClass').click(function(){
			$('#collapse-' + genome + type + 'SubClass').collapse('toggle');
		});
	});

	// for each subclass section
	$.each([["antigen", "ag"], ["celltype", "cl"]], function(it, type){
		$('select#' + genome + type[1] + 'Class').change(function(){
			// Common variables
			var genomeSelected = $('.genomeTab ul li.active a').text().replace(/[\n\s ]/g, "");
			var valueSelected  = $('select#' + genomeSelected + type[1] + 'Class option:selected').val();
			var subClassObj    = indexAll[genomeSelected][type[0]][valueSelected];

			// Erase previous options
			$('select#' + genomeSelected + type[1] + 'SubClass').empty();

			// Generate an option for All
			$("<option>")
				.attr("value", "-")
				.attr("selected", "true")
				.append("All")
				.appendTo('select#' + genomeSelected + type[1] + 'SubClass');

			// Generate options from subClassObj
			$.map(subClassObj, function(value, key){
				return [[key, value]];
			}).sort().forEach(function(element, index, array){
				var k = element[0];
				var v = element[1];
				$('<option>')
					.attr("value", k)
					.append(k + " (" + v + ")")
					.appendTo('select#' + genomeSelected + type[1] + 'SubClass');
			});

			// activate typeahead
			var typeaheadInput = $('#' + genomeSelected + type[1] + 'SubClass.typeahead');
			var subClassList = $.map(subClassObj, function(value, key){
						return key;
					});

			// Erase previous data set
			typeaheadInput.typeahead('destroy');

			var list = new Bloodhound({
				datumTokenizer: Bloodhound.tokenizers.whitespace,
				queryTokenizer: Bloodhound.tokenizers.whitespace,
				local: subClassList
			});

			typeaheadInput.typeahead({
				hint: true,
				highlight: true,
				minLength: 1
			},{
				name: 'list',
				source: list
			});

			// sync textbox and input field
			typeaheadInput.keyup(function(){
				var input = $(this).val();
				if($.inArray(input,subClassList) > -1){
					$('select#' + genomeSelected + type[1] + 'SubClass').val(input);
				}
			});
			typeaheadInput.on('typeahead:select', function(){
				var input = $(this).val();
				if($.inArray(input,subClassList) > -1){
					$('select#' + genomeSelected + type[1] + 'SubClass').val(input);
				}
			});
		});
	})

	// hide another subclass when one subclass is selected
	var twoSelectors = ['select#' + genome + 'agSubClass', 'select#' + genome + 'clSubClass'];
	$.each(twoSelectors, function(i, selector){
		$(selector).change(function(){
			if($(twoSelectors[0]).val() != "-" && $(twoSelectors[1]).val() != "-"){

				// build alert message object
				var span = $('<span>').attr("aria-hidden","true").append("×")

				var button = $('<button>').attr("type","button").attr("class","close")
							.attr("data-dismiss","alert").attr("aria-label","Close").append(span);

				var message = $('<div>').attr("class","alert alert-warning alert-dismissible fade in")
							.attr("role","alert").append(button)
							.append('Select one SubClass disables another').append('</div>');

				switch($(this).attr("id").replace(genome,"").replace("SubClass","")){
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
		});
	});
});

// tab trigger event
$('a[data-toggle="tab"]').on('shown.bs.tab', function(e){
	var activatedTab = e.target;
	var previousTab = e.relatedTarget;
	var genome = $('.genomeTab ul li.active a').text().replace(/[\n\s ]/g, "");
	$.each(["ag","cl"], function(i, value){
		$('select#' + genome + value + 'SubClass').empty();
	})
});

// send data to get igv url
$(function(){
	$("button#submit").click(function(){
		var button = $(this);
		button.attr("disabled", true);

		var genome = $('.genomeTab ul li.active a').text().replace(/[\n\s ]/g, "");
		var data = {
			// igv: $().text
			condition: {
				genome: genome,
				agClass: $('#' + genome + 'agClass option:selected').val(),
				agSubClass: $('#' + genome + 'agSubClass option:selected').val(),
				clClass: $('#' + genome + 'clClass option:selected').val(),
				clSubClass: $('#' + genome + 'clSubClass option:selected').val(),
				qval: $('#' + genome + 'qval option:selected').val()
			}
		};

		alert(JSON.stringify(data));

		$.ajax({
			type : 'post',
			url : "/browse",
			data: JSON.stringify(data),
			contentType: 'application/json',
			dataType: 'json',
			scriptCharset: 'utf-8',
			success : function(response) {
				alert(JSON.stringify(response));
				window.open(response.url, "_self", "")
			},
			error : function(response){
				alert(JSON.stringify(response));
				alert("error!");
			},
			complete: function(){
				button.attr("disabled", false);
			}
		});
	})
})
