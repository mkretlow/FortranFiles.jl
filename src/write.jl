import Base: write

"""
    write(f::FortranFile, items...)
    write(f::FortranFile, rec=N, items...)

Write a data record to a `FortranFile`. Each `item` should be a scalar
of a Fortran-compatible datatype (e.g. `Int32`, `Float64`, `FString{10}`),
or an array of such scalars. If no `item`s are given, an empty record is
written. Returns the number of bytes written, **not** including the space
taken up by the record markers.

For direct-access files, the number of the record to be written must be
specified with the `rec` keyword (N=1 for the first record).
"""
function write(f::FortranFile, items...)
   fwrite(f, items...)
end

function write(f::FortranFile{DirectAccess}, items...; rec::Integer=0)
   if rec==0
      error("direct-access files require specifying the record to be written (use rec keyword argument)")
   end
   gotorecord(f, rec)
   fwrite(f, items...)
end

function fwrite( f::FortranFile )
   rec = Record(f, 0)
   close(rec)
   return 0
end

function fwrite( f::FortranFile, vars... )
   # how much data to write?
   towrite = sum( sizeof_var(var) for var in vars )
   rec = Record(f, towrite)
   written = sum( write_var(rec,var) for var in vars )
   close(rec)
   return written
end

# workarounds for "does not support byte I/O"
function write_var( rec::Record, var::Int8 )
   write_var( rec, [var] )
end

function write_var( rec::Record, arr::Array{Int8,N} ) where {N}
   write(rec, arr)
end

# write scalars
function write_var( rec::Record, var::T ) where {T}
   write( rec, rec.convert.onwrite(var) )
end

# write arrays
function write_var( rec::Record, arr::Array{T,N} ) where {T,N}
   written = 0
   for x in arr
      written += write(rec, rec.convert.onwrite(x))
   end
   return written
end

# write strings: delegate to data field
write_var( rec::Record, var::FString ) = write_var(rec, var.data)
# TODO: the following triggers internal error on method resolution for julia-0.7
write_var( rec::Record, arr::Array{FString{L},N} ) where {L,N} = write_fstrings(rec, arr)
write_fstrings( rec::Record, arr::Array{FString{L},N} ) where {L,N} = sum( write_var(rec, var.data) for var in arr )

# specialized versions for no byte-order conversion
write_var( rec::RecordWithSubrecords{NOCONV}, arr::Array{T,N} ) where {T,N} = write(rec, arr)
write_var( rec::RecordWithSubrecords{NOCONV}, arr::Array{Int8,N} ) where {N} = write(rec, arr)
write_var( rec::RecordWithoutSubrecords{R,NOCONV}, arr::Array{T,N} ) where {T,N,R} = write(rec, arr)
write_var( rec::RecordWithoutSubrecords{R,NOCONV}, arr::Array{Int8,N} ) where {N,R} = write(rec, arr)

# resolve ambiguities
write_var( rec::RecordWithSubrecords{NOCONV}, arr::Array{FString{L},N} ) where {L,N} = write_fstrings(rec, arr)
write_var( rec::RecordWithoutSubrecords{R,NOCONV}, arr::Array{FString{L},N} ) where {L,N,R} = write_fstrings(rec, arr)

check_fortran_type(x::Array{T}) where {T} = check_fortran_type(x[1])
check_fortran_type(x::FString) = true
check_fortran_type(x::T) where {T} = isbits(T)

function sizeof_var( var::T ) where {T}
   check_fortran_type(var) || error("cannot serialize datatype $T for Fortran")
   sizeof(var)
end

