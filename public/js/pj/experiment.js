// Main initialization
$(function () {
  initializeExperimentPage();
});

// Configuration
const DB_NAMESPACES = {
  wikigenes: "https://www.wikigenes.org/?search=",
  posmed:
    "http://omicspace.riken.jp/PosMed/search?actionType=searchexec&keyword=",
  pdbj: "http://pdbj.org/mine/search?query=",
  atcc: "http://www.atcc.org/Search_Results.aspx?searchTerms=",
  mesh: "https://www.ncbi.nlm.nih.gov/mesh/?term=",
  rikenbrc: "http://www2.brc.riken.jp/lab/cell/list.cgi?skey=",
};

const HELP_TEXT = {
  threshold:
    "Set the threshold for statistical significance values calculated by peak-caller MACS2 (-10*Log10[MACS2 Q-value]). If 50 is set here, peaks with Q value < 1E-05 are shown on genome browser IGV.",
  viewOnIGV:
    'IGV must be running on your computer before clicking the button.\n\nIf your browser shows "cannot open the page" error, launch IGV and allow an access via port 60151 (from the menu bar of IGV, View > Preferences... > Advanced > "enable port" and set port number 60151) to browse the data. If you have not installed IGV on your computer, visit https://www.broadinstitute.org/igv/download or google "Integrative Genomics Viewer" to download the software.',
  distributionInfo:
    'Distribution of sequence reads and called peaks across all experiments within the same experiment type (antigen class for ChIP-Seq). The orange horizontal line indicates the position of this experiment. For Bisulfite-Seq experiments, "peaks" should be interpreted as "hyper-methylated regions."',
  clusteringInfo:
    "Hierarchical clustering based on correlations among experiments sharing the same context (i.e., the combination of genome, antigen, and cell type). The arrowheads indicate this experiment, and their colors represent the median correlation of this experiment against all other experiments.",
};

// Utility functions
function getUrlParameter(param) {
  const urlParams = new URLSearchParams(window.location.search);
  return urlParams.get(param);
}

function initializeExperimentPage() {
  setupDatabaseLinks();
  setupAnalysisLinks();
  setupHelpButtons();
  hideAnalysisForBisulfiteSeq();
  initializeStatistics();
  setupActionButtons();
}

// Database link functionality
function setupDatabaseLinks() {
  $("button").on("click", function (event) {
    event.preventDefault();
    const namespace = DB_NAMESPACES[$(this).attr("id")];
    if (!namespace) return;

    let query;
    if ($(this).hasClass("antigen")) {
      query = $("input#queryAntigen").val();
    } else if ($(this).hasClass("celltype")) {
      query = $("input#queryCelltype").val();
    }

    if (query) {
      const encodedQuery = query.replace(/\s/g, "+");
      window.open(namespace + encodedQuery);
    }
  });
}

// Analysis links functionality
function setupAnalysisLinks() {
  const expid = getUrlParameter("id");
  if (!expid) return;

  $.ajax({
    type: "GET",
    url: "/data/exp_metadata.json?expid=" + expid,
    dataType: "json",
  }).done(function (records) {
    records.forEach((record) => {
      const genome = record.genome;
      const baseUrl = `https://chip-atlas.dbcls.jp/data/${genome}`;
      const analysisLinks = [
        ["Colocalization", `${baseUrl}/colo/${expid}.html`],
        ["Target Genes (TSS ± 1kb)", `${baseUrl}/target/${expid}.1.html`],
        ["Target Genes (TSS ± 5kb)", `${baseUrl}/target/${expid}.5.html`],
        ["Target Genes (TSS ± 10kb)", `${baseUrl}/target/${expid}.10.html`],
      ];

      checkAndDisplayAnalysisLinks(analysisLinks, genome);
    });
  });
}

function checkAndDisplayAnalysisLinks(links, genome) {
  const $container = $(`ul#analysisLinkOut.${genome}`);
  let validLinksCount = 0;

  links.forEach((link, index) => {
    const [text, url] = link;

    $.ajax({
      type: "GET",
      url: "/api/remoteUrlStatus?url=" + url,
      complete: function (transport) {
        if (transport.status === 200) {
          $container.append(`<li><a href="${url}">${text}</a></li>`);
          validLinksCount++;
        }

        if (index === links.length - 1 && validLinksCount === 0) {
          $container.append(
            "<li class='dropdown-header'>No data available for this record</li>",
          );
        }
      },
    });
  });
}

// Help functionality
function setupHelpButtons() {
  $(".infoBtn").click(function () {
    const helpId = $(this).attr("id");
    if (HELP_TEXT[helpId]) {
      alert(HELP_TEXT[helpId]);
    }
  });
}

// Hide analysis for specific experiment types
function hideAnalysisForBisulfiteSeq() {
  const $analysisButton = $("div#analyze-dropdown");
  if ($analysisButton.attr("experiment") === "Bisulfite-Seq") {
    $analysisButton.hide();
  }
}

// Statistics panel initialization
function initializeStatistics() {
  const $statisticsPanel = $("#statistics-panel");
  const $sections = $(".statistics-section");

  if ($sections.length === 0) return;

  let hasAvailableData = false;
  let sectionsProcessed = 0;

  $sections.each(function () {
    const $section = $(this);
    checkStatisticsSection($section).then((sectionHasData) => {
      sectionsProcessed++;

      if (sectionHasData) {
        hasAvailableData = true;
        $section.show();
      } else {
        $section.hide();
      }

      if (sectionsProcessed === $sections.length && hasAvailableData) {
        $statisticsPanel.show();
        setupStatisticsInteractions();
      }
    });
  });
}

function checkStatisticsSection($section) {
  const distributionUrl = $section.data("distribution-url");
  const correlationUrl = $section.data("correlation-url");

  const distributionCheck = checkImage(
    distributionUrl,
    $section.find(".distribution-container"),
  );
  const correlationCheck = checkImage(
    correlationUrl,
    $section.find(".correlation-container"),
  );

  return Promise.all([distributionCheck, correlationCheck]).then((results) => {
    const hasData = results.some(Boolean);

    if (hasData) {
      $section.find(".info-section").show();
      if (results[1]) {
        // correlation image exists
        $section.find(".download-container").show();
      }
    }

    return hasData;
  });
}

function checkImage(url, $container) {
  return new Promise((resolve) => {
    const img = new Image();
    const $loadingIndicator = $container.find(".loading-indicator");
    const $img = $container.find("img");

    img.onload = () => {
      $loadingIndicator.hide();
      $img.show();
      resolve(true);
    };

    img.onerror = () => {
      $loadingIndicator.hide();
      resolve(false);
    };

    img.src = url;
  });
}

// Statistics interactions setup
function setupStatisticsInteractions() {
  setupImageClickHandlers();
  setupDownloadHandlers();
  setupSeparators();
}

function setupImageClickHandlers() {
  $(".distribution-img, .correlation-img")
    .css("cursor", "pointer")
    .on("click", function () {
      const $img = $(this);
      const imgSrc = $img.attr("src");
      const imgAlt = $img.attr("alt");
      showImageModal(imgSrc, imgAlt);
    });
}

function showImageModal(src, alt) {
  const modalHtml = `
    <div class="modal fade" id="imageModal" tabindex="-1" role="dialog">
      <div class="modal-dialog modal-lg" role="document">
        <div class="modal-content">
          <div class="modal-header">
            <button type="button" class="close" data-dismiss="modal" aria-label="Close">
              <span aria-hidden="true">&times;</span>
            </button>
            <h4 class="modal-title">${alt}</h4>
          </div>
          <div class="modal-body text-center">
            <img src="${src}" class="img-responsive" alt="${alt}" style="max-width: 100%; height: auto;">
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-default" data-dismiss="modal">Close</button>
          </div>
        </div>
      </div>
    </div>
  `;

  $("#imageModal").remove();
  $("body").append(modalHtml);
  $("#imageModal").modal("show");
}

function setupDownloadHandlers() {
  $(".download-tsv")
    .attr("title", "Download detailed correlation data in TSV format")
    .on("click", function (e) {
      e.preventDefault();
      const $button = $(this);
      const url = $button.data("url");
      const filename = $button.data("filename");

      downloadFile(url, filename, $button);
    });
}

function downloadFile(url, filename, $button) {
  const originalText = $button.html();
  $button
    .html('<i class="fas fa-spinner fa-spin"></i> Downloading...')
    .prop("disabled", true);

  const restoreButton = () => {
    $button.html(originalText).prop("disabled", false);
  };

  if (
    typeof fetch !== "undefined" &&
    window.URL &&
    window.URL.createObjectURL
  ) {
    fetch(url)
      .then((response) => {
        if (!response.ok)
          throw new Error(`Network response was not ok: ${response.status}`);
        return response.blob();
      })
      .then((blob) => {
        const blobUrl = window.URL.createObjectURL(blob);
        const link = document.createElement("a");
        link.href = blobUrl;
        link.download = filename;
        link.style.display = "none";

        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);

        setTimeout(() => window.URL.revokeObjectURL(blobUrl), 100);
        restoreButton();
      })
      .catch(() => fallbackDownload(url, filename, restoreButton));
  } else {
    fallbackDownload(url, filename, restoreButton);
  }
}

function fallbackDownload(url, filename, callback) {
  try {
    const link = document.createElement("a");
    link.href = url;
    link.download = filename;
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    link.style.display = "none";

    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);

    callback();
  } catch (error) {
    console.error("Download failed:", error);
    window.open(url, "_blank");
    callback();
    alert(
      "File opened in new tab. Use your browser's save function to download it.",
    );
  }
}

function setupSeparators() {
  const $visibleSections = $(".statistics-section:visible");
  if ($visibleSections.length > 1) {
    $visibleSections.each(function (index) {
      if (index < $visibleSections.length - 1) {
        $(this).find(".genome-separator").show();
      }
    });
  }
}

function setupActionButtons() {
  $(".btn.dropdown-toggle").each(function () {
    const $btn = $(this);
    const text = $btn.text().trim();
    $btn.attr("title", `Click to see ${text.toLowerCase()} options`);
  });
}
