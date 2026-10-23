"
I turn an entry into the part of its key that says how its lane is ordered. That part
alone, not the whole key: the marker in front of it belongs to the lane's section, and
behind me there is only padding. No single participant knows the whole key -- the lane
description puts my part into its section (SoilQueueLaneDescription>>#keyFor:in:).

Which is why the entry hands over values and not a key. If a subclass of the entry
answered its own sort key, key building would sit in the seam that is meant to carry
domain matters only, and two entries of one lane could end up sorting differently.

Everything I write is fixed length and big endian, so that byte order and numeric order
agree -- an index compares keys as numbers.

How a lane is read follows from how its keys are ordered, so that is mine too: which
entry is due next, how many are, and which key an entry lies under once its due time has
changed. What I answer is how a lane ordered by due time is read -- the first pending
key is the oldest, and the first one that is not due says that none behind it is. A
format that orders otherwise answers the three for itself; the workspace never asks
which kind of format a lane has.
"
Class {
	#name : #SoilQueueKeyFormat,
	#superclass : #Object,
	#category : #'Soil-Queue'
}

{ #category : #testing }
SoilQueueKeyFormat class >> isAbstract [

	^ self == SoilQueueKeyFormat
]

{ #category : #converting }
SoilQueueKeyFormat >> appendKeyPartsFor: anEntry in: aLaneDescription of: aQueueWorkspace on: aWriteStream [
	"add my part of the key for an entry that comes into a lane, and nothing else. Most
	formats need nothing but the entry; one that numbers its entries has to look at what
	the lane holds already, and the workspace is where that is read"

	^ self subclassResponsibility
]

{ #category : #reading }
SoilQueueKeyFormat >> dueIn: aLaneDescription of: aQueueWorkspace at: aDateAndTime skipping: aCollection upTo: aLimit do: aBlock [
	"what the dispatcher reads of a lane, in one walk: how many of its entries are due,
	leaving out the keys in aCollection and counting no further than aLimit, and when the
	next one after aDateAndTime falls due. aBlock gets the two. The time is nil when the
	count reached aLimit -- the workers it asks for are all the lane can have, and they come
	back for more -- and when nothing comes after.

	In my order both lie on one walk: the due entries come first, and the first one that is
	not due is the time. Only pending entries count. One that says claimed is with a worker,
	or waiting for the recovery pass, and neither asks for another worker; a key that is out
	is passed without its entry being read"

	| count range |
	count := 0.
	range := aLaneDescription range.
	aQueueWorkspace
		scanFrom: range firstIndexKey
		to: range lastIndexKey
		do: [ :key :entryBlock |
			(aCollection includes: key) ifFalse: [
				| entry |
				entry := entryBlock value.
				entry isPending ifTrue: [
					entry readyAt > aDateAndTime ifTrue: [
						^ aBlock value: count value: entry readyAt ].
					count := count + 1.
					count >= aLimit ifTrue: [ ^ aBlock value: count value: nil ] ] ].
			key + 1 ].
	^ aBlock value: count value: nil
]

{ #category : #converting }
SoilQueueKeyFormat >> keyFor: anEntry movedFrom: anIndexKey in: aLaneDescription of: aQueueWorkspace [
	"the key an entry lies under once its due time may have changed -- a follow-up later, a
	backoff. The due time is in my keys, so that is a key built anew, and the same one when
	the due time did not change"

	^ (aLaneDescription keyFor: anEntry in: aQueueWorkspace)
		asIndexKeyOfSize: aQueueWorkspace keySize
]

{ #category : #reading }
SoilQueueKeyFormat >> nextDueIn: aLaneDescription of: aQueueWorkspace at: aDateAndTime skipping: aCollection preferring: aPreferredKey after: aLastKey ifNone: aBlock [
	"the key of the oldest entry of a lane that is due, skipping the keys that are already
	out. The two keys are for a format that hands out by group; I ignore them. When nothing
	is due, aBlock is evaluated with the time the next entry becomes due, or with nil when
	no pending entry is left that is not out -- so a caller can sleep exactly as long as it
	has to rather than come back and ask again.

	Only pending entries are handed out. An entry that says claimed belongs to a worker, or
	to the recovery pass if no worker holds it -- and it stays in the ordering either way,
	because a claim does not change a key. Without this a claimed entry nobody holds -- one
	of the run before, until the first step gives it back, or one whose giving back failed
	-- would be handed out at once, refused by its own claim, and sent to be given back
	again, for ever. A key that is out is passed without its entry being read"

	| range |
	range := aLaneDescription range.
	aQueueWorkspace
		scanFrom: range firstIndexKey
		to: range lastIndexKey
		do: [ :key :entryBlock |
			(aCollection includes: key) ifFalse: [
				| entry |
				entry := entryBlock value.
				entry isPending ifTrue: [
					entry readyAt <= aDateAndTime ifTrue: [ ^ key ].
					^ aBlock cull: entry readyAt ] ].
			key + 1 ].
	^ aBlock cull: nil
]

{ #category : #accessing }
SoilQueueKeyFormat >> partsSize [
	"how many bytes my part of a key takes -- a lane of mine needs that much room behind its
	marker"

	^ self subclassResponsibility
]
