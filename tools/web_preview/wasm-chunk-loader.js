/* Original Good Boys Web preview adapter. Uses only standard browser APIs. */
(function () {
  'use strict';

  const manifest = __GOOD_BOYS_WASM_MANIFEST__;
  const originalFetch = globalThis.fetch.bind(globalThis);
  const wasmURL = new URL(manifest.wasm, document.baseURI);

  function reportDownloadError(error) {
    console.error('Good Boys game download failed:', error);
    if (typeof globalThis.dispatchEvent === 'function') {
      globalThis.dispatchEvent(new CustomEvent('goodboys-load-error', {
        detail: { message: 'The game download was interrupted. Reload to try again.' },
      }));
    }
  }

  globalThis.fetch = async function goodBoysFetch(input, init) {
    let target;
    try {
      target = new URL(input instanceof Request ? input.url : input, document.baseURI);
    } catch (_) {
      return originalFetch(input, init);
    }
    if (target.origin !== globalThis.location.origin ||
        target.origin !== wasmURL.origin || target.pathname !== wasmURL.pathname) {
      return originalFetch(input, init);
    }

    const request = new Request(input, init);
    if (request.method !== 'GET' || request.headers.has('range')) {
      return originalFetch(input, init);
    }

    const controller = new AbortController();
    const abort = () => controller.abort(request.signal.reason);
    if (request.signal.aborted) abort();
    else request.signal.addEventListener('abort', abort, { once: true });

    let reader = null;
    let nextPart = 0;
    let partBytes = 0;
    let completeBytes = 0;
    let stopped = false;

    function release() {
      request.signal.removeEventListener('abort', abort);
    }

    async function openPart(index) {
      const part = manifest.parts[index];
      const url = new URL(part.file, wasmURL);
      // Preserve the caller's relevant fetch policy and cancellation, but each
      // request retrieves one complete file rather than a range of the original.
      const result = await originalFetch(url, {
        method: 'GET',
        headers: request.headers,
        mode: request.mode,
        credentials: request.credentials,
        cache: request.cache,
        redirect: request.redirect,
        referrer: request.referrer,
        referrerPolicy: request.referrerPolicy,
        signal: controller.signal,
      });
      if (!result.ok) {
        throw new Error('Game part ' + (index + 1) + ' returned HTTP ' + result.status);
      }
      if (!result.body) throw new Error('Game part ' + (index + 1) + ' has no body');
      partBytes = 0;
      return result.body.getReader();
    }

    // Reject the fetch immediately if the first part cannot be retrieved.
    // Later failures reject the response stream rather than returning bad bytes.
    try {
      reader = await openPart(0);
    } catch (error) {
      stopped = true;
      release();
      if (!request.signal.aborted) reportDownloadError(error);
      throw error;
    }

    const body = new ReadableStream({
      async pull(stream) {
        try {
          while (!stopped) {
            const result = await reader.read();
            if (stopped) return;
            if (!result.done) {
              partBytes += result.value.byteLength;
              completeBytes += result.value.byteLength;
              if (partBytes > manifest.parts[nextPart].bytes) {
                throw new Error('Game part ' + (nextPart + 1) + ' is larger than expected');
              }
              stream.enqueue(result.value);
              return;
            }
            reader.releaseLock();
            reader = null;
            if (partBytes !== manifest.parts[nextPart].bytes) {
              throw new Error('Game part ' + (nextPart + 1) + ' ended before its expected size');
            }
            nextPart += 1;
            if (nextPart === manifest.parts.length) {
              if (completeBytes !== manifest.bytes) throw new Error('Game download size mismatch');
              stopped = true;
              release();
              stream.close();
              return;
            }
            reader = await openPart(nextPart);
          }
        } catch (error) {
          if (stopped) return;
          stopped = true;
          controller.abort();
          release();
          if (!request.signal.aborted) reportDownloadError(error);
          stream.error(error);
        }
      },
      async cancel(reason) {
        stopped = true;
        controller.abort();
        release();
        if (reader) {
          try { await reader.cancel(reason); } catch (_) { /* Already aborted. */ }
        }
      },
    });

    return new Response(body, {
      status: 200,
      statusText: 'OK',
      headers: {
        'Content-Type': 'application/wasm',
        'Content-Length': String(manifest.bytes),
      },
    });
  };
}());
