"
I turn an entry into the part of its key that says how the queue is ordered. That part
alone, not the whole key: the marker in front of it belongs to the section the queue
lies in, and whatever the embedder wants to add comes after me. No single participant
knows the whole key -- the queue passes the build along and each adds its own piece.

Which is why the entry hands over values and not a key. If a subclass of the entry
answered its own sort key, key building would sit in the seam that is meant to carry
domain matters only, and two entries of one queue could end up sorting differently.

Everything I write is fixed length and big endian, so that byte order and numeric order
agree -- an index compares keys as numbers.
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
	"add my part of the key for an entry that comes into a lane. Most formats need nothing
	but the entry; one that numbers its entries has to look at what the lane holds already,
	and the workspace is where that is read"

	^ self appendKeyPartsFor: anEntry on: aWriteStream
]

{ #category : #converting }
SoilQueueKeyFormat >> appendKeyPartsFor: anEntry on: aWriteStream [
	"add my part of the key for anEntry, and nothing else"

	^ self subclassResponsibility
]

{ #category : #testing }
SoilQueueKeyFormat >> ordersByDueTime [
	"whether the due time is in my keys. If it is, an entry whose due time changes has to
	move to a new key, and the first entry of a lane that is not due says that none behind
	it is. If not, the key stays where it is and the due time is read from the entry"

	^ self subclassResponsibility
]

{ #category : #accessing }
SoilQueueKeyFormat >> partsSize [
	"how many bytes my part of a key takes -- a lane of mine needs that much room behind its
	marker"

	^ self subclassResponsibility
]
