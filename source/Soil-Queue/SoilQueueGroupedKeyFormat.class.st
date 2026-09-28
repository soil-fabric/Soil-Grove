"
The format that keeps the entries of a group in order: the group first, then a sequence
number within it, then the entry's id.

The group comes first so that all entries of one group lie together and the first of
them is the one to go next. The sequence says where in the group an entry stands, and it
is handed out here when the entry comes in -- one more than the last one the group holds
in the transaction that adds it, so that entries added in one transaction keep the order
they were added in.

The id comes last, and it is not there for the order. An index does not notice two
transactions writing the same key: the one that commits second overwrites the first,
without a word. Two transactions adding to one group at the same time both see the same
last entry and draw the same number, and without the id one of the two entries would be
gone. With it both stay, and their order between them is open -- which is right, because
two entries added side by side never had one.

Duplicate keys in the index would do without the sequence, but their order is what the
index happens to do and nothing it promises, and every key operation of the queue would
have to name the entry besides the key.

The due time is not in the key. It stays on the entry, so an entry that has to wait holds
up its group where it is instead of moving behind the others: of a chain, the next step
must not run before the one ahead of it.

The width of a group id is mine, eight bytes unless said otherwise. The sequence takes
four, the id eight.
"
Class {
	#name : #SoilQueueGroupedKeyFormat,
	#superclass : #SoilQueueKeyFormat,
	#instVars : [
		'groupIdSize'
	],
	#category : #'Soil-Queue'
}

{ #category : #'instance creation' }
SoilQueueGroupedKeyFormat class >> groupIdSize: anInteger [

	^ self new setGroupIdSize: anInteger
]

{ #category : #converting }
SoilQueueGroupedKeyFormat >> appendKeyPartsFor: anEntry in: aLaneDescription of: aQueueWorkspace on: aWriteStream [

	| group last sequence |
	group := self groupBytesOf: anEntry.
	last := aQueueWorkspace
		lastKeyFrom: (self firstKeyOfGroup: group in: aLaneDescription range)
		to: (self lastKeyOfGroup: group in: aLaneDescription range).
	sequence := last
		ifNil: [ 1 ]
		ifNotNil: [ (self sequenceIn: last behind: aLaneDescription range width) + 1 ].
	sequence >= (256 raisedTo: 4) ifTrue: [
		^ self error: 'the group of ' , anEntry printString , ' has used up its sequence numbers' ].
	aWriteStream
		nextPutAll: group;
		nextPutAll: (sequence asByteArrayOfSize: 4);
		nextPutAll: anEntry id
]

{ #category : #converting }
SoilQueueGroupedKeyFormat >> appendKeyPartsFor: anEntry on: aWriteStream [
	"my part of a key cannot be told from the entry alone: where it stands in its group
	depends on what the group holds already"

	^ self error: 'a grouped key needs the lane and the workspace it goes into'
]

{ #category : #accessing }
SoilQueueGroupedKeyFormat >> firstKeyOfGroup: aGroup in: aRange [
	"the lowest key a group can have in a section: the group, and nothing behind it"

	^ aRange keyWith: aGroup
]

{ #category : #accessing }
SoilQueueGroupedKeyFormat >> firstKeyOfGroupOf: aKey in: aRange [

	^ self firstKeyOfGroup: (self groupIn: aKey of: aRange) in: aRange
]

{ #category : #converting }
SoilQueueGroupedKeyFormat >> groupBytesOf: anEntry [
	"the group id of anEntry in my width. A negative number is refused rather than written,
	because #asByteArrayOfSize: drops the sign without a word, and -5 would share a group
	with 5"

	| group |
	group := anEntry groupId.
	group ifNil: [ ^ self error: anEntry printString , ' has no group id for a grouped lane' ].
	group isInteger ifTrue: [
		group < 0 ifTrue: [ ^ self error: 'a group id cannot be negative: ' , group printString ].
		^ group asByteArrayOfSize: groupIdSize ].
	(group isKindOf: ByteArray) ifFalse: [
		^ self error: 'a group id is an integer or a byte array, not ' , group printString ].
	group size = groupIdSize ifFalse: [
		^ self error: 'a group id of ' , group size printString , ' bytes where '
			, groupIdSize printString , ' are expected' ].
	^ group
]

{ #category : #accessing }
SoilQueueGroupedKeyFormat >> groupIn: aKey of: aRange [
	"the group a key of a section belongs to: the bytes behind the section's marker"

	| start |
	start := aRange width + 1.
	^ aKey copyFrom: start to: start + groupIdSize - 1
]

{ #category : #accessing }
SoilQueueGroupedKeyFormat >> groupIdSize [

	^ groupIdSize
]

{ #category : #initialization }
SoilQueueGroupedKeyFormat >> initialize [

	super initialize.
	groupIdSize := 8
]

{ #category : #accessing }
SoilQueueGroupedKeyFormat >> lastKeyOfGroup: aGroup in: aRange [
	"the highest key a group can have in a section: every byte behind the group set"

	^ aRange keyWith: aGroup , (ByteArray new: 12 withAll: 255)
]

{ #category : #accessing }
SoilQueueGroupedKeyFormat >> lastKeyOfGroupOf: aKey in: aRange [

	^ self lastKeyOfGroup: (self groupIn: aKey of: aRange) in: aRange
]

{ #category : #testing }
SoilQueueGroupedKeyFormat >> ordersByDueTime [

	^ false
]

{ #category : #accessing }
SoilQueueGroupedKeyFormat >> partsSize [
	"the group id, four bytes of sequence, eight of id"

	^ groupIdSize + 12
]

{ #category : #converting }
SoilQueueGroupedKeyFormat >> sequenceIn: aKey behind: aMarkerWidth [
	"where the entry under aKey stands in its group -- the four bytes behind the marker and
	the group id"

	| start |
	start := aMarkerWidth + groupIdSize + 1.
	^ (aKey copyFrom: start to: start + 3) asInteger
]

{ #category : #initialization }
SoilQueueGroupedKeyFormat >> setGroupIdSize: anInteger [

	anInteger < 1 ifTrue: [ ^ self error: 'a group id needs at least one byte' ].
	groupIdSize := anInteger
]
