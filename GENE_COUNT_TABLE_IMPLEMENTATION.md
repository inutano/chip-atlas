# Gene Count Table Implementation for ChIP-Atlas Enrichment Analysis

## Overview

This document describes the implementation of a new "Gene count table" option in the ChIP-Atlas Enrichment Analysis tool. The feature adds a third radio button option to panel "4. Enter dataset A" alongside the existing "Genomic regions (BED)" and "Gene list (Gene symbols or IDs)" options.

## Changes Made

### 1. Frontend UI Changes (views/enrichment_analysis.haml)

**Location**: Panel 4 - "Enter dataset A"

**Changes**:
- Added a third radio button option for "Gene count table"
- Added corresponding info button with help text

```haml
.checkbox.panel-input
  %label
    %input{ type: "radio", id: "#{genome}UserDataCount", name: "bedORGene", value: "count" }
    Gene count table
    %a.infoBtn{ id: "#{genome}UserDataCount" }
      &#x24D8;
```

### 2. JavaScript Functionality (public/js/pj/enrichment_analysis.js)

#### 2.1 Radio Button Event Handler
**Location**: Line 74-87
**Changes**: Added case for "count" value

```javascript
$("input[name='bedORGene']").change(function () {
  var genome = genomeSelected();
  switch ($(this).val()) {
    case "bed":
      positionBed();
      break;
    case "gene":
      positionGene();
      break;
    case "count":
      positionCount();
      break;
  }
  eraseTextarea(genome + "UserData");
});
```

#### 2.2 New positionCount() Function
**Location**: After positionGene() function
**Purpose**: Hide panel 5 (dataset B) when count option is selected

```javascript
function positionCount() {
  var genome = genomeSelected();
  // Hide panel 5 (dataset B) completely when count is selected
  $("#" + genome + "TargetDB")
    .parent()
    .hide();

  var panels = {
    ".panel-input.rnd": "hide",
    ".panel-input.distTSS": "hide",
    ".panel-input.gene.default-hide": "hide",
    ".panel-input.bed": "hide",
    ".panel-input.bed-input.comparedWith": "hide",
  };
  var inputs = {
    ComparedWithRefseq: "unchecked",
    ComparedWithBed: "unchecked",
    ComparedWithRandom: "unchecked",
    ComparedWithRandomx1: "unchecked",
    ComparedWithUserlist: "unchecked",
  };
  setForms(panels, inputs);
  setDistance(0);
}
```

#### 2.3 Updated positionBed() and positionGene() Functions
**Changes**: Added code to show panel 5 when switching away from count option

```javascript
function positionBed() {
  var genome = genomeSelected();
  // Show panel 5 (dataset B) when bed is selected
  $("#" + genome + "TargetDB")
    .parent()
    .show();
  // ... rest of function
}

function positionGene() {
  var genome = genomeSelected();
  // Show panel 5 (dataset B) when gene is selected
  $("#" + genome + "TargetDB")
    .parent()
    .show();
  // ... rest of function
}
```

#### 2.4 API Data Preparation (retrievePostData function)
**Location**: Lines 544-579
**Changes**: Special handling for count type

```javascript
function retrievePostData() {
  // ... existing code
  var typeA = $(
    "#" + genome + '-tab-content input[name="bedORGene"]:checked',
  ).val();

  var data = {
    // ... existing fields
    typeA: typeA,
    // ... rest of data object
  };

  // Special handling for count type
  if (typeA === "count") {
    data.typeA = "count";
    // For count type, put the content in dataset A and clear dataset B
    data.bedBFile = "";
    data.typeB = "";
  }

  return data;
}
```

#### 2.5 Data Validation Updates (evaluateText function)
**Changes**: Skip validation of dataset B fields when using count type

```javascript
function evaluateText(data) {
  var descSet = [
    [data["bedAFile"], "bed", "User data bed file"],
    [data["descriptionA"], "desc", "User data title"],
    [data["distanceUp"], "dist", "Distance down range"],
    [data["distanceDown"], "dist", "Distance up range"],
    [data["title"], "desc", "Project title"],
  ];

  // Only validate bedBFile and descriptionB if not using count type
  if (data["typeA"] !== "count") {
    descSet.push([data["bedBFile"], "bed", "Compared data bed file"]);
    descSet.push([data["descriptionB"], "desc", "Compared data title"]);
  }
  // ... rest of validation logic
}
```

#### 2.6 Time Estimation Updates (estimateTime function)
**Changes**: Added case for count type in time calculation

```javascript
function estimateTime(userData, comparedWith, numRef) {
  // ... existing code
  switch (
    $("#" + genome + '-tab-content input[name="bedORGene"]:checked').val()
  ) {
    case "bed":
      // ... existing bed logic
      break;
    case "gene":
      // ... existing gene logic
      break;
    case "count":
      // For count type, use a simple estimation since no dataset B comparison
      var seconds = getSeconds(
        numLinesUserData,
        0, // no dataset B for count type
        numRef,
        "bed",
      );
      break;
  }
  // ... rest of function
}
```

#### 2.7 Help Text and Info Button Support
**Changes**: Added help text for count option and case in switch statement

```javascript
// Help text addition
var helpText = {
  // ... existing help texts
  userdatacount:
    "Check this to upload a gene count table for differential expression analysis. The table should contain gene identifiers and their corresponding counts.\n\n",
  // ... rest of help texts
};

// Info button case addition
switch ($(this).attr("id")) {
  // ... existing cases
  case genome + "UserDataCount":
    alert(helpText["userdatacount"]);
    break;
  // ... rest of cases
}
```

#### 2.8 Example Data Support (putUserData function)
**Changes**: Added case for count type example data

```javascript
function putUserData(type) {
  var genome = genomeSelected();
  switch (type) {
    case "bed":
      getExampleData(genome, "bedA.txt", genome + "UserData");
      break;
    case "gene":
      getExampleData(genome, "geneA.txt", genome + "UserData");
      break;
    case "count":
      getExampleData(genome, "countA.txt", genome + "UserData");
      break;
  }
}
```

### 3. Example Data Files

**Created**: Example count table files for all supported genomes
**Locations**:
- `public/examples/hg19/countA.txt`
- `public/examples/hg38/countA.txt`
- `public/examples/mm9/countA.txt`
- `public/examples/mm10/countA.txt`
- `public/examples/rn6/countA.txt`
- `public/examples/dm3/countA.txt`
- `public/examples/dm6/countA.txt`
- `public/examples/ce10/countA.txt`
- `public/examples/ce11/countA.txt`
- `public/examples/sacCer3/countA.txt`

**Format**: Tab-separated values with header
```
gene_id	count
ADI1	245
AGO1	1832
AHCYL2	567
...
```

## Functional Behavior

### When "Gene count table" is selected:

1. **Panel 5 (dataset B) is hidden**: The entire panel becomes invisible to the user
2. **Form validation updated**: Dataset B fields are not validated
3. **API data preparation**: 
   - `typeA` is set to "count"
   - `typeB` is set to empty string
   - `bedBFile` is set to empty string
   - Count table content goes into `bedAFile` field
4. **Time estimation**: Uses simplified calculation without dataset B comparison
5. **Example data**: Loads count table format when "Try with example" is clicked

### When switching away from "Gene count table":

1. **Panel 5 becomes visible again**: Users can select dataset B options
2. **Form validation restored**: All standard validation rules apply
3. **Standard API behavior**: Normal typeA/typeB handling resumes

## API Integration

The backend WABI API endpoint receives the following data structure for count type:

```json
{
  "typeA": "count",
  "bedAFile": "gene_id\tcount\nGATA1\t1234\nSOX2\t5678\n...",
  "typeB": "",
  "bedBFile": "",
  // ... other standard fields
}
```

## Testing

A comprehensive test suite was created (`test/count_functionality_test.js`) that verifies:

1. Panel 5 hiding/showing behavior
2. Data structure correctness for API calls
3. Function transitions between different input types
4. Validation logic updates
5. Form state management

## Files Modified

1. `views/enrichment_analysis.haml` - Added third radio button
2. `public/js/pj/enrichment_analysis.js` - All JavaScript functionality
3. `public/examples/*/countA.txt` - Example data files (10 genomes)

## Files Created

1. `test/enrichment_test.html` - Manual testing interface
2. `test/count_functionality_test.js` - Automated test suite
3. `GENE_COUNT_TABLE_IMPLEMENTATION.md` - This documentation

## Compatibility

- Maintains full backward compatibility with existing bed/gene functionality
- No changes required to backend API endpoints
- No changes to existing CSS or other frontend assets
- Gracefully handles all genome types supported by ChIP-Atlas

## Future Considerations

- The count table format could be extended to support additional metadata columns
- Custom validation rules could be added specifically for count data
- Integration with differential expression analysis workflows could be enhanced
- Custom time estimation formulas could be developed for count-specific analyses