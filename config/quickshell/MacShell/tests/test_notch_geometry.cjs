const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const geometry = vm.createContext({});
vm.runInContext(fs.readFileSync(`${__dirname}/../NotchGeometry.js`, 'utf8').replace(/^\.pragma library\s*/, ''), geometry);
const shape = vm.createContext({Geometry: geometry});
vm.runInContext(fs.readFileSync(`${__dirname}/../NotchShape.js`, 'utf8').replace(/^\.(pragma|import).*$/gm, ''), shape);

test('parallel panel, menu and control contours use inner radius plus padding', () => {
    assert.equal(geometry.panelRadius, geometry.contentRadius + geometry.padding);
    assert.equal(geometry.menuRadius, geometry.controlRadius + geometry.menuPadding);
    for (const size of [16, 24, 48, 80, 96]) {
        const r = geometry.innerRadius(36, 16, size, size);
        assert.ok(r >= 0 && r <= size / 2);
    }
    assert.equal(geometry.innerRadius(10, 3, 28, 28), 7);
    assert.equal(geometry.innerRadius(8, 12, 28, 28), 0);
});

test('navigation end caps retain concentric insets at different heights and page counts', () => {
    for(const height of [160, 200, 240])for(const count of [5, 6, 7]) {
        const rail = geometry.rail(height, count);
        const selection = geometry.innerRadius(rail.radius, geometry.railPadding, rail.width-2*geometry.railPadding, rail.cell);
        assert.ok(Math.abs(rail.radius-selection-geometry.railPadding)<1e-6);
        assert.ok(Math.abs(rail.radius+rail.edge-geometry.panelRadius)<1e-6);
        assert.ok(rail.height <= height);
    }
});

test('the painted surface and clipping path keep finite geometry through transitions', () => {
    for(const mode of ['attached','floating'])for(const wide of [true,false])for(const t of [0,.1,.4,.8,1]) {
        const path = shape.path(520,28+172*t,mode,t,wide);
        assert.ok(!/NaN|Infinity|undefined/.test(path));
        assert.ok(path.startsWith('M ') && path.endsWith('Z'));
        assert.equal(geometry.inset(mode,wide), geometry.wing(mode,1,wide)+geometry.padding);
    }
});


test('surface radii and wings follow the same scale as inner cards', () => {
    for(const scale of [.7,.85,1,1.2])for(const mode of ['attached','floating']) {
        let move,edge;
        const pen={beginPath(){},moveTo(x,y){move=[x,y];},lineTo(x,y){if(!edge)edge=[x,y];},quadraticCurveTo(){},bezierCurveTo(){},closePath(){}};
        shape.trace(pen,520*scale,120*scale,mode,1,true,scale);
        const outer=mode==='attached'?120*scale-edge[1]:move[0];
        assert.ok(Math.abs(outer/scale-geometry.panelRadius)<1e-6);
        if(mode==='attached')assert.ok(Math.abs(edge[0]/scale-24)<1e-6);
        assert.ok(Math.abs(outer/scale-geometry.contentRadius-geometry.padding)<1e-6);
    }
});
