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
SoilQueueKeyFormat >> appendKeyPartsFor: anEntry on: aWriteStream [
	"add my part of the key for anEntry, and nothing else"

	^ self subclassResponsibility
]
