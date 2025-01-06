#!/usr/bin/env bash
perl -pe 's/enum (SubsectionType|VersionType|VersionEnum)(?!.*: uint$)/enum $1 : uint/g' -i MsPdb.cs
