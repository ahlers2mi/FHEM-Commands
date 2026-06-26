/*
 * fhemweb_custom_link.js  (Teil des FHEM-Moduls 98_Commands.pm)
 *
 * Blendet neben der oberen FHEMWEB-Befehlszeile (input.maininput) einen Link
 * auf die Detailseite eines Geraets ein. Ziel und Beschriftung kommen aus der
 * Query der eigenen Script-URL, die das Modul beim Registrieren setzt, z.B.:
 *     pgm2/fhemweb_custom_link.js?dev=myCommander&label=Commands
 * Damit bleibt die Datei generisch (eine Datei fuer beliebig viele Geraete).
 */
(function () {
  var me = (document.currentScript && document.currentScript.src) || "";
  function qp(n) {
    var m = me.match(new RegExp("[?&]" + n + "=([^&]*)"));
    return m ? decodeURIComponent(m[1].replace(/\+/g, " ")) : "";
  }
  var dev   = qp("dev");
  var label = qp("label") || "Commands";

  function init() {
    if (!dev) return;
    if (document.getElementById("cmdCommandsLink")) return;
    var inp = document.querySelector("input.maininput");
    if (!inp) return;

    if (!document.getElementById("cmdCommandsLinkCss")) {
      var st = document.createElement("style");
      st.id = "cmdCommandsLinkCss";
      st.textContent =
        "#cmdCommandsLink:hover{filter:brightness(1.35)}" +
        "#cmdCommandsLink svg{width:15px;height:15px;margin:0;flex:0 0 auto}";
      document.head.appendChild(st);
    }

    var cs = getComputedStyle(inp);
    var a = document.createElement("a");
    a.id = "cmdCommandsLink";
    a.href = "?detail=" + encodeURIComponent(dev);
    a.title = label;
    ["backgroundColor", "borderTop", "borderRight", "borderBottom", "borderLeft",
     "borderRadius", "color", "boxShadow", "fontFamily", "fontSize", "fontWeight"
    ].forEach(function (p) { a.style[p] = cs[p]; });
    a.style.display = "inline-flex";
    a.style.alignItems = "center";
    a.style.gap = "6px";
    a.style.boxSizing = "border-box";
    a.style.padding = "0 10px";
    a.style.marginLeft = "10px";
    a.style.textDecoration = "none";
    a.style.lineHeight = "1";
    a.style.whiteSpace = "nowrap";
    a.style.flex = "0 0 auto";
    a.style.height = inp.getBoundingClientRect().height + "px";

    var icon =
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' +
      'stroke-linecap="round" stroke-linejoin="round">' +
      '<polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>';
    a.innerHTML = icon + label.replace(/</g, "&lt;");

    var form = inp.closest("form") || inp.parentNode;
    form.style.display = "flex";
    form.style.alignItems = "center";
    inp.style.flex = "0 0 auto";
    inp.style.verticalAlign = "";

    inp.insertAdjacentElement("afterend", a);
  }

  if (typeof jQuery !== "undefined") { jQuery(init); }
  else if (document.readyState !== "loading") { init(); }
  else { document.addEventListener("DOMContentLoaded", init); }
})();
