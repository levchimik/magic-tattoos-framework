Scriptname NiOverride Native Hidden

bool Function HasOverlays(ObjectReference akActor) global native
Function AddOverlays(ObjectReference akActor) global native
Function AddNodeOverrideString(ObjectReference akActor, bool isFemale, string node, int key, int index, string data, bool persist) global native
Function AddNodeOverrideInt(ObjectReference akActor, bool isFemale, string node, int key, int index, int data, bool persist) global native
Function AddNodeOverrideFloat(ObjectReference akActor, bool isFemale, string node, int key, int index, float data, bool persist) global native
Function ApplyNodeOverrides(ObjectReference akActor) global native
bool Function HasNodeOverride(ObjectReference akActor, bool isFemale, string node, int key, int index) global native
Function RemoveNodeOverride(ObjectReference akActor, bool isFemale, string node, int key, int index) global native
