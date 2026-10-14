// Pune iconița jocului (icons/icon.ico) în șablonul de export Windows al Godot.
// Godot 4.3 are nevoie de rcedit pentru asta; aici folosim pachetul npm resedit.
// Rulează: node tools/set_windows_icon.mjs <șablon original.exe> icons/icon.ico <șablon nou.exe>
import * as ResEdit from 'resedit';
import * as PELibrary from 'pe-library';
import fs from 'fs';
const [,, input, ico, output] = process.argv;
const exe = PELibrary.NtExecutable.from(fs.readFileSync(input), { ignoreCert: true });
const res = PELibrary.NtExecutableResource.from(exe);
const iconFile = ResEdit.Data.IconFile.from(fs.readFileSync(ico));
const groups = ResEdit.Resource.IconGroupEntry.fromEntries(res.entries);
const target = groups.length ? groups[0] : { id: 1, lang: 1033 };
ResEdit.Resource.IconGroupEntry.replaceIconsForResource(res.entries, target.id, target.lang, iconFile.icons.map(i => i.data));
res.outputResource(exe);
fs.writeFileSync(output, Buffer.from(exe.generate()));
console.log('groups', groups.map(g => g.id), 'icons', iconFile.icons.length);
