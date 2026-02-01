// let _wasmInstance;
let module;
let _inited = false;
const U32_MAX = 0xFFFF_FFFF;
self.addEventListener('message', async (event) => {
    if (_inited) {
        const result = module.process_wasm(event.data.id, event.data.payload);
        self.postMessage({ code: result.code, bytes: result.bytes });
        return;
    }
    if (event.data.inline) {
        const blob = new Blob([event.data.glue], { type: "application/javascript" });
        const moduleUrl = URL.createObjectURL(blob);
        module = await import(moduleUrl);
    } else {
        module = await import(event.data.glue);
    }
    await module.initSync(event.data.wasm);
    _inited = true;
    const version = module.process_wasm(U32_MAX, new Uint8Array());
    self.postMessage({ code: version.code, bytes: version.bytes });

});