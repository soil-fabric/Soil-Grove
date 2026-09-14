"
An entry that classifies its errors instead of taking the default: everything it throws
is #retriable. It exists so a test can show that the classification is the subclass's
call and that the base's #permanent really is only a default.
"
Class {
	#name : #SoilQueueTestRetriableEntry,
	#superclass : #SoilQueueTestEntry,
	#category : #'Soil-Queue-Tests'
}

{ #category : #working }
SoilQueueTestRetriableEntry >> classifyError: anError [

	^ #retriable
]
