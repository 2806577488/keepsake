/*
 * Keepsake Mermaid 桥接脚本。
 *
 * 由离屏 WebView 加载：window.__keepsakeRender(id, code) 渲染完成后，把 SVG 字符串
 * 通过 JavaScriptChannel（KeepsakeMermaidBridge）回传给 Dart 侧，再用 flutter_svg 画。
 *
 * 全部用 ES5 写，避免老一点点的 WebView 内核不认新语法。
 */
(function () {
  // flutter_svg 不解析 mermaid 输出的 <style> 选择器，所以这里把最终计算样式内联到每个元素上。
  var STYLE_PROPS = [
    'fill',
    'fill-opacity',
    'fill-rule',
    'stroke',
    'stroke-width',
    'stroke-opacity',
    'stroke-dasharray',
    'stroke-linecap',
    'stroke-linejoin',
    'opacity',
    'font-family',
    'font-size',
    'font-weight',
    'font-style',
    'text-anchor',
    'dominant-baseline'
  ];

  function reply(id, payload) {
    try {
      if (window.KeepsakeMermaidBridge && window.KeepsakeMermaidBridge.postMessage) {
        window.KeepsakeMermaidBridge.postMessage(JSON.stringify(payload));
      }
    } catch (e) {
      // 通道不可用就算了，Dart 侧会超时回退成代码块。
    }
  }

  function fail(id, message) {
    reply(id, { id: id, error: String(message || 'mermaid 渲染失败') });
  }

  function styleMap(node) {
    var map = {};
    var raw = node.getAttribute('style') || '';
    var parts = raw.split(';');
    for (var i = 0; i < parts.length; i++) {
      var idx = parts[i].indexOf(':');
      if (idx > 0) {
        map[parts[i].slice(0, idx).trim()] = parts[i].slice(idx + 1).trim();
      }
    }
    return map;
  }

  function serializeStyle(map) {
    var out = '';
    for (var key in map) {
      if (Object.prototype.hasOwnProperty.call(map, key)) {
        out += key + ':' + map[key] + ';';
      }
    }
    return out;
  }

  function inlineStyles(svg) {
    var nodes = svg.querySelectorAll('*');
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      if (!node.tagName) continue;
      var tag = node.tagName.toLowerCase();
      if (tag === 'style' || tag === 'foreignobject') continue;
      var computed = window.getComputedStyle(node);
      var map = styleMap(node);
      for (var j = 0; j < STYLE_PROPS.length; j++) {
        var value = computed.getPropertyValue(STYLE_PROPS[j]);
        if (value) {
          map[STYLE_PROPS[j]] = value;
        }
      }
      node.setAttribute('style', serializeStyle(map));
    }
    // mermaid 默认带一段 <style>；选择器 flutter_svg 支持不全，去掉以免干扰。
    var styles = svg.querySelectorAll('style');
    for (var k = 0; k < styles.length; k++) {
      if (styles[k].parentNode) styles[k].parentNode.removeChild(styles[k]);
    }
    // htmlLabels 在 Dart 侧已经关掉，这里再兜底清一次 foreignObject（flutter_svg 不支持）。
    var foreign = svg.querySelectorAll('foreignObject');
    for (var n = 0; n < foreign.length; n++) {
      if (foreign[n].parentNode) foreign[n].parentNode.removeChild(foreign[n]);
    }
  }

  function svgSize(svg) {
    var viewBox = svg.getAttribute('viewBox');
    if (!viewBox) {
      var box = svg.getBBox();
      viewBox = box.x + ' ' + box.y + ' ' + box.width + ' ' + box.height;
      svg.setAttribute('viewBox', viewBox);
    }
    var parts = viewBox.split(/[\s,]+/).map(Number);
    var width = parts[2] > 0 ? parts[2] : 1;
    var height = parts[3] > 0 ? parts[3] : 1;
    return { width: width, height: height };
  }

  function parseMarkerRef(value) {
    if (!value) return null;
    var match = /url\(\s*['"]?#([^'")]+)/.exec(value);
    return match ? match[1] : null;
  }

  function markerTransform(el, marker, atStart) {
    if (!el.getTotalLength) return null;
    var length = el.getTotalLength();
    if (!(length > 0)) return null;
    var eps = Math.min(0.5, Math.max(length / 1000, 0.01));
    var a;
    var b;
    if (atStart) {
      a = el.getPointAtLength(0);
      b = el.getPointAtLength(eps);
    } else {
      a = el.getPointAtLength(length - eps);
      b = el.getPointAtLength(length);
    }
    var angle = (Math.atan2(b.y - a.y, b.x - a.x) * 180) / Math.PI;
    var point = atStart ? a : b;
    var refX = parseFloat(marker.getAttribute('refX') || '0') || 0;
    var refY = parseFloat(marker.getAttribute('refY') || '0') || 0;
    var markerWidth = parseFloat(marker.getAttribute('markerWidth') || '3') || 3;
    var markerHeight = parseFloat(marker.getAttribute('markerHeight') || '3') || 3;
    var sx = 1;
    var sy = 1;
    var viewBox = marker.getAttribute('viewBox');
    if (viewBox) {
      var parts = viewBox.split(/[\s,]+/).map(Number);
      if (parts[2] > 0) sx = markerWidth / parts[2];
      if (parts[3] > 0) sy = markerHeight / parts[3];
    }
    var units = marker.getAttribute('markerUnits') || 'strokeWidth';
    if (units !== 'userSpaceOnUse') {
      var strokeWidth = parseFloat(window.getComputedStyle(el).getPropertyValue('stroke-width')) || 1;
      sx *= strokeWidth;
      sy *= strokeWidth;
    }
    return (
      'translate(' + point.x + ',' + point.y + ') rotate(' + angle + ') scale(' + sx + ',' + sy + ')' +
      ' translate(' + -refX + ',' + -refY + ')'
    );
  }

  // flutter_svg 不认 <marker>，这里把箭头/圆点 marker 展开成普通 <g transform>，保证箭头还在。
  function flattenMarkers(svg) {
    var markerNodes = svg.querySelectorAll('marker');
    if (!markerNodes.length) return;
    var markers = {};
    for (var i = 0; i < markerNodes.length; i++) {
      markers[markerNodes[i].getAttribute('id')] = markerNodes[i];
    }
    var attrs = ['marker-start', 'marker-end', 'marker-mid'];
    var targets = svg.querySelectorAll('[marker-start],[marker-end],[marker-mid]');
    for (var t = 0; t < targets.length; t++) {
      var el = targets[t];
      for (var k = 0; k < attrs.length; k++) {
        var attr = attrs[k];
        var raw = el.getAttribute(attr);
        if (!raw) continue;
        var atStart = attr === 'marker-start';
        var id = attr === 'marker-mid' ? null : parseMarkerRef(raw);
        var marker = id ? markers[id] : null;
        try {
          if (marker) {
            var transform = markerTransform(el, marker, atStart);
            if (transform) {
              var group = document.createElementNS('http://www.w3.org/2000/svg', 'g');
              group.setAttribute('transform', transform);
              var markerStyle = marker.getAttribute('style');
              if (markerStyle) group.setAttribute('style', markerStyle);
              for (var c = 0; c < marker.children.length; c++) {
                group.appendChild(marker.children[c].cloneNode(true));
              }
              if (el.parentNode) el.parentNode.insertBefore(group, el.nextSibling);
            }
          }
        } catch (e) {
          // 单个箭头失败不影响整张图
        }
        el.removeAttribute(attr);
      }
    }
    for (var m = 0; m < markerNodes.length; m++) {
      if (markerNodes[m].parentNode) markerNodes[m].parentNode.removeChild(markerNodes[m]);
    }
  }

  window.__keepsakeRender = function (id, code) {
    if (!window.mermaid) {
      fail(id, 'mermaid 未加载');
      return;
    }
    try {
      window.mermaid.initialize({
        startOnLoad: false,
        securityLevel: 'strict',
        theme: 'default',
        fontFamily: 'sans-serif',
        flowchart: { htmlLabels: false, useMaxWidth: false },
        sequence: { useMaxWidth: false },
        gantt: { useMaxWidth: false },
        class: { useMaxWidth: false },
        state: { useMaxWidth: false },
        er: { useMaxWidth: false },
        pie: { useMaxWidth: false },
        journey: { useMaxWidth: false },
        mindmap: { useMaxWidth: false },
        timeline: { useMaxWidth: false }
      });
      window.mermaid.render('keepsake-mermaid-' + id, code).then(
        function (result) {
          // mermaid 需要元素在文档里才能算出 getBBox / computed style，挂到屏幕外量尺寸。
          var holder = document.createElement('div');
          holder.setAttribute('style', 'position:absolute;left:-100000px;top:0;');
          holder.innerHTML = result.svg;
          document.body.appendChild(holder);
          try {
            var svg = holder.querySelector('svg');
            if (!svg) {
              throw new Error('mermaid 没有输出 SVG');
            }
            inlineStyles(svg);
            flattenMarkers(svg);
            var size = svgSize(svg);
            svg.setAttribute('width', String(size.width));
            svg.setAttribute('height', String(size.height));
            var out = new XMLSerializer().serializeToString(svg);
            reply(id, { id: id, svg: out });
          } catch (e) {
            fail(id, e && e.message ? e.message : e);
          } finally {
            if (holder.parentNode) holder.parentNode.removeChild(holder);
          }
        },
        function (err) {
          fail(id, err && err.message ? err.message : err);
        }
      );
    } catch (e) {
      fail(id, e && e.message ? e.message : e);
    }
  };
})();
