!=====================================================================
!       Genera o lee las condiciones iniciales (Campos u,v,w,p)
!       Inicializa las arrays para estadisticas
!	Lee la malla en la direccion Y
!
! Lee todos los planos YX donde estan los campos y la presion en R*4 y
! los copia en R*8 en los buffers (u,v,w,p). 
!
!  El master se copia su campo correspondiente y luego envia como R*4 los trozos a
!  los otros cores que se lo copian como R*8
!
!       ACHTUNG!!    allocates one input plane, check there is space
!==========================================================================




subroutine getstartzy(u,v,w,p,dt,mpiid,communicator)
  use alloc_dns
  use statistics
  use names
  use point
  use genmod
  use ctesp
  use hdf5
  use h5lt

  implicit none
  include "mpif.h"
  integer,intent(in):: communicator
  ! ---------------------------- I/O -----------------------------------!
  real(8),dimension(nz1,ny,ib:ie)  :: v,p
  real(8),dimension(nz1,ny+1,ib:ie):: u,w
  real(4), dimension(:,:,:),allocatable:: resu 
  real*8,dimension(:),allocatable::dummy

  ! -------------------------- Work ----------------------------------------!
  integer status(MPI_STATUS_SIZE),ierr,mpiid,commu,tipo,nfile,mpiw1,mpiw2,mpiw3,mpiw4
  integer nxr,nyr,nzr,nz1r,nzz,j,i,k,l,dot,lim2,rsize,irec,rsize1,rsize2,ji
  real(8) jk,dt,dum(20),timer
  character text*99, uchar*1
  character(len=256):: fil1,fil2,fil3,fil4

  ! -------------------------- HDF5 ------------------------------------!
  integer(hid_t):: fid,pid
  integer:: h5err
  integer:: info
  integer(hsize_t), dimension(3):: dims,offset
  integer(HSIZE_T), dimension(1):: hdims

  ! --------------------------  Programa  ----------------------------------!
  commu=communicator
  tipo=MPI_REAL4

  fil1=trim(chinit)//'.u'
  fil2=trim(chinit)//'.v'
  fil3=trim(chinit)//'.w'
  fil4=trim(chinit)//'.p'

#ifdef RPARALLEL
  call MPI_INFO_CREATE(info,ierr)
  !       lee el fichero 
  if (mpiid.eq.0) then
     write(*,*) 'Leyendo del fichero'
     write(*,*) fil1     
     call readheader(fil1,nxr,nyr,nzr)
  endif

  call MPI_BCAST(nxr,1,mpi_integer,0,commu,ierr)
  call MPI_BCAST(nzr,1,mpi_integer,0,commu,ierr)
  call MPI_BCAST(nyr,1,mpi_integer,0,commu,ierr)

  if (ny.ne.nyr) then
     if (mpiid==0) write(*,*) 'changing the y grid has to be done separately'
     if (mpiid==0) write(*,*) 'ny=',ny,'nyr',nyr
     stop
  elseif (nx.ne.nxr) then
     if (mpiid==0) write(*,*) 'changing the x grid has to be done separately'
     if (mpiid==0) write(*,*) 'nx=',nx,'nxr',nxr
  endif

  u = 0d0
  v = 0d0
  w = 0d0
  p = 0d0
  nz1r = 2*(nzr+1)
  nzz = min(nz1r,nz1)

  !Allocate the temporary array to read U and W.
  dims = (/ nz1r, nyr+1, ie-ib+1 /)
  offset = (/ 0, 0, 0 /)
  allocate(resu(nz1r,nyr+1,ie-ib+1))

  !Collective call to the properties list creator

  timer = MPI_WTIME()

  call h5pcreate_f(H5P_FILE_ACCESS_F,pid,h5err)
  call h5pset_fapl_mpiposix_f(pid,commu,.true.,h5err)
  call h5fopen_f(trim(fil1)//".h5",H5F_ACC_RDONLY_F,fid,h5err,pid)
  call h5pclose_f(pid,h5err)

  !Load the data to the allocated array and close the file
  call h5load_parallel(fid,"value",3,dims,mpiid,nummpi,commu,info,resu,h5err)
  !Close the file
  call h5fclose_f(fid,h5err)

  if(mpiid == 0) then
     write(*,*) "File dimensons", nz1r, nyr, nxr
     write(*,*) "Read ", nz1r*(nyr+1)*(nxr)*4/1024/1024, "MiB in ", MPI_WTIME()-timer
  end if

  !Copy the data to the variable preserving the layout
  call MPI_BARRIER(commu,ierr)
  u(1:nzz,1:nyr+1,ib:ie) = real(resu(1:nzz,1:nyr+1,1:ie-ib+1),kind=8)
  call MPI_BARRIER(commu,ierr)

  !Read the rest of the variables.
  call h5pcreate_f(H5P_FILE_ACCESS_F,pid,h5err)
  call h5pset_fapl_mpiposix_f(pid,commu,.true.,h5err)
  call h5fopen_f(trim(fil3)//".h5",H5F_ACC_RDONLY_F,fid,h5err,pid)
  call h5pclose_f(pid,h5err)
  call h5load_parallel(fid,"value",3,dims,mpiid,nummpi,commu,info,resu,h5err)
  call h5fclose_f(fid,h5err)

  call MPI_BARRIER(commu,ierr)
  w(1:nzz,1:nyr+1,ib:ie) = real(resu(1:nzz,1:nyr+1,1:ie-ib+1),kind=8)
  call MPI_BARRIER(commu,ierr)

  ! No more variables with ny+1
  deallocate(resu)

  !Allocate the temporary array to read V and P.
  dims = (/ nz1r, nyr, ie-ib+1 /)
  allocate(resu(nz1r,nyr,ie-ib+1))

  call h5pcreate_f(H5P_FILE_ACCESS_F,pid,h5err)
  call h5pset_fapl_mpiposix_f(pid,commu,.true.,h5err)
  call h5fopen_f(trim(fil2)//".h5",H5F_ACC_RDONLY_F,fid,h5err,pid)
  call h5pclose_f(pid,h5err)
  call h5load_parallel(fid,"value",3,dims,mpiid,nummpi,commu,info,resu,h5err)
  call h5fclose_f(fid,h5err)

  call MPI_BARRIER(commu,ierr)
  v(1:nzz,1:nyr,ib:ie) = real(resu(1:nzz,1:nyr,1:ie-ib+1),kind=8)

!!!RESET THE V0 VALUE AT THE INFLOW
  ! if (mpiid == 0) then
  !    call h5fopen_f("./v0.h5",H5F_ACC_RDONLY_F,fid,h5err,H5P_DEFAULT_F)
  !    hdims = (/ ny /)
  !    call H5LTread_dataset_double_f_1(fid,"v",v0,hdims,h5err)
  !    call h5fclose_f(fid,h5err)
  !    v(1,1:ny,1)=v0
  !    write(*,*) "WARNING: SUCCESSFULLY UPDATED V0 AT THE INFLOW"
  ! end if

  call MPI_BARRIER(commu,ierr)

  call h5pcreate_f(H5P_FILE_ACCESS_F,pid,h5err)
  call h5pset_fapl_mpiposix_f(pid,commu,.true.,h5err)
  call h5fopen_f(trim(fil4)//".h5",H5F_ACC_RDONLY_F,fid,h5err,pid)
  call h5pclose_f(pid,h5err)
  call h5load_parallel(fid,"value",3,dims,mpiid,nummpi,commu,info,resu,h5err)
  call h5fclose_f(fid,h5err)

  call MPI_BARRIER(commu,ierr)
  p(1:nzz,1:nyr,ib:ie) = real(resu(1:nzz,1:nyr,1:ie-ib+1),kind=8)
  call MPI_BARRIER(commu,ierr)

  deallocate(resu)

  if(mpiid == 0) then
     u0=u(1,1:ny+1,1)
     v0=v(1,1:ny,1)
  end if
  !    write(*,*) mpiid, "File read successfully from ", ib, "to ", ie
#endif


#ifdef RSERIAL
  if (mpiid.eq.0) then
     write(*,*) 'Leyendo del fichero con la interfaz serial:'
     write(*,*) fil1     
     call readheader(fil1,nxr,nyr,nzr)
  endif

  call MPI_BCAST(nxr,1,mpi_integer,0,commu,ierr)
  call MPI_BCAST(nzr,1,mpi_integer,0,commu,ierr)
  call MPI_BCAST(nyr,1,mpi_integer,0,commu,ierr)

  if (ny.ne.nyr) then
     if (mpiid==0) write(*,*) 'changing the y grid has to be done separately'
     if (mpiid==0) write(*,*) 'ny=',ny,'nyr',nyr
     stop
  elseif (nx.ne.nxr) then
     if (mpiid==0) write(*,*) 'changing the x grid has to be done separately'
     if (mpiid==0) write(*,*) 'nx=',nx,'nxr',nxr
  endif

  u = 0d0
  v = 0d0
  w = 0d0
  p = 0d0
  nz1r = 2*(nzr+1)
  nzz = min(nz1r,nz1)

  !Allocate the temporary array to read U and W.
  dims = (/ nz1r, nyr+1, ie-ib+1 /)
  offset = (/ 0, 0, 0 /)
  allocate(resu(nz1r,nyr+1,ie-ib+1))
  resu = 0.0

  if (mpiid == 0) write(*,*) resu(nz1r,0,1:10)

  !Collective call to the properties list creator
  timer = MPI_WTIME()

  if (mpiid == 0) write(*,*) 'Leyendo el campo'

  if (mpiid == 0) call h5fopen_f(trim(fil1)//".h5",H5F_ACC_RDONLY_F,fid,h5err)
  call h5load_serial(fid,"value",dims,offset,nummpi,commu,resu,h5err)
  if (mpiid == 0) call h5fclose_f(fid,h5err)

  if(mpiid == 0) then
     write(*,*) "File dimensons", nz1r, nyr, nxr
     write(*,*) "Read ", nz1r*(nyr+1)*(nxr)*4/1024/1024, "MiB in ", MPI_WTIME()-timer
  end if

  !Copy the data to the variable preserving the layout
  call MPI_BARRIER(commu,ierr)
  u(1:nzz,1:nyr+1,ib:ie) = real(resu(1:nzz,1:nyr+1,1:ie-ib+1),kind=8)
  call MPI_BARRIER(commu,ierr)


  !Read the rest of the variables.
  if (mpiid == 0) call h5fopen_f(trim(fil3)//".h5",H5F_ACC_RDONLY_F,fid,h5err)
  call h5load_serial(fid,"value",dims,offset,nummpi,commu,resu,h5err)
  if (mpiid == 0) call h5fclose_f(fid,h5err)

  call MPI_BARRIER(commu,ierr)
  w(1:nzz,1:nyr+1,ib:ie) = real(resu(1:nzz,1:nyr+1,1:ie-ib+1),kind=8)
  call MPI_BARRIER(commu,ierr)

  ! No more variables with ny+1
  deallocate(resu)

  !Allocate the temporary array to read V and P.
  dims = (/ nz1r, nyr, ie-ib+1 /)
  allocate(resu(nz1r,nyr,ie-ib+1))
  resu = 0.0


  if (mpiid == 0) call h5fopen_f(trim(fil2)//".h5",H5F_ACC_RDONLY_F,fid,h5err)
  call h5load_serial(fid,"value",dims,offset,nummpi,commu,resu,h5err)
  if (mpiid == 0) call h5fclose_f(fid,h5err)

  call MPI_BARRIER(commu,ierr)
  v(1:nzz,1:nyr,ib:ie) = real(resu(1:nzz,1:nyr,1:ie-ib+1),kind=8)

  call MPI_BARRIER(commu,ierr)


  if (mpiid == 0)call h5fopen_f(trim(fil4)//".h5",H5F_ACC_RDONLY_F,fid,h5err)
  call h5load_serial(fid,"value",dims,offset,nummpi,commu,resu,h5err)
  if (mpiid == 0)call h5fclose_f(fid,h5err)

  call MPI_BARRIER(commu,ierr)
  p(1:nzz,1:nyr,ib:ie) = real(resu(1:nzz,1:nyr,1:ie-ib+1),kind=8)
  call MPI_BARRIER(commu,ierr)

  deallocate(resu)

  if(mpiid == 0) then
     u0=u(1,1:ny+1,1)
     v0=v(1,1:ny,1)
  end if
  !    write(*,*) mpiid, "File read successfully from ", ib, "to ", ie
#endif

  if(mpiid.eq.0) then      
     write(*,*) 'Values of Y grid and Um after reading:'
     write(*,*) '      y            um      u0            v0     ' 
     write(*,*) '---------------------------------'    
     do i=1,4   
        write(*,'(4f12.9)') y(i-1),um(i),u0(i),v0(i)
     enddo
     write(*,*) '---------------------------------'    
     do i=ny-3,ny+1   
        write(*,'(4f12.9)') y(i-1),um(i),u0(i),v0(i)
     enddo
  endif
  if(mpiid.eq.0) write(*,*) 'BROADCASTING TIEMPO,Y,DT'  
  call MPI_BCAST(tiempo,1,mpi_real8,0,commu,ierr)
  call MPI_BCAST(y,ny+2,mpi_real8,0,commu,ierr) !need by coeft!!
  call MPI_BCAST(dt,1,mpi_real8,0,commu,ierr)       
  if(mpiid.eq.0) write(*,*) 'DONE BROADCASTING'
end subroutine getstartzy



! -------------------------------------------------------------------! 
! -------------------------------------------------------------------! 
! -------------------------------------------------------------------! 
! ---------------------  READING SUBROUTINES ------------------------! 
! -------------------------------------------------------------------! 
! -------------------------------------------------------------------! 
! -------------------------------------------------------------------! 
subroutine h5load_parallel(fid,name,ndims,dims,rank,&
     & size,comm,info,data,ierr)

  use hdf5

  implicit none

  include "mpif.h"

  integer(hid_t), intent(in):: fid
  character(len=*), intent(in):: name
  integer, intent(in):: ndims
  integer(hsize_t), dimension(ndims), intent(in):: dims
  integer, intent(in):: rank,size
  integer, intent(in):: comm,info
  real(kind = 4),intent(out):: data
  integer(hid_t), intent(out):: ierr

  integer(hid_t):: dset
  integer(hid_t):: dspace,mspace
  integer(hid_t):: plist_id
  integer(hsize_t), dimension(ndims):: start,nooffset,totaldims
  integer, dimension(size):: lastdims
  integer:: mpierr

  integer:: i,lastdim

  start = 0
  nooffset = 0
  totaldims = dims

  lastdim = dims(ndims) ! Don't mess with ints and longs

  call MPI_ALLGATHER(lastdim,1,MPI_INTEGER,lastdims,1,MPI_INTEGER,comm,mpierr)

  totaldims(ndims) = sum(lastdims)

  !Open the global dataset and get the global dataspace
  call h5dopen_f(fid,name,dset,ierr)
  call h5dget_space_f(dset,dspace,ierr)

  !Create the local dataset
  call h5screate_simple_f(ndims,dims,mspace,ierr)
  call h5sselect_hyperslab_f(mspace,H5S_SELECT_SET_F,nooffset,dims,ierr)

  !Select the hyperslab in the global dataset
  start(ndims) = sum(lastdims(1:rank+1))-lastdims(rank+1)
  call h5sselect_hyperslab_f(dspace,H5S_SELECT_SET_F,start,dims,ierr)

  !Create data transfer mode property list                                                                                                                          
  call h5pcreate_f(H5P_DATASET_XFER_F,plist_id,ierr)
  call h5pset_dxpl_mpio_f(plist_id,H5FD_MPIO_COLLECTIVE_F,ierr)

  !Commit the memspace to the disk
  call h5dread_f(dset,H5T_NATIVE_REAL,data,dims,ierr,mspace,dspace,plist_id)

  !Close property list                                                                                                                                              
  call h5pclose_f(plist_id,ierr)

  !Close datasets and dataspaces
  call h5sclose_f(mspace,ierr)
  call h5dclose_f(dset,ierr)   
  call h5sclose_f(dspace,ierr)

end subroutine h5load_parallel

subroutine h5load_serial(fid,name,dims,offset,size,comm,data,ierr)
  ! Routine to read hdf5 datasets with real data in serial filesystems
  ! Only the master node reads and then it spreads the data to the
  ! rest of worker nodes.
  
  ! It sums the dimensions of all the callers and reads from the offset,
  ! concatenating the data in the last given dimension (the one further
  ! from the aligned)
  
  ! It can do stuff like this.
  
  ! ooooooooooooooooooooooooooooooooooooooooooooo
  ! ooooooo112233445566oooooooooooooooooooooooooo
  ! ooooooo112233445566oooooooooooooooooooooooooo
  ! ooooooo112233445566oooooooooooooooooooooooooo
  use hdf5
  
  implicit none
  
  include "mpif.h"
  
  integer(hid_t), intent(in):: fid
  character(len=*), intent(in):: name
  integer(hsize_t), dimension(3), intent(in):: dims
  integer(hsize_t), dimension(3), intent(in):: offset
  integer, intent(in):: size
  integer, intent(in):: comm
  real(kind = 4), dimension(dims(1),dims(2),dims(3)), intent(out):: data
  integer(hid_t), intent(out):: ierr
  
  integer(hid_t):: dset
  integer(hid_t):: dspace,mspace
  integer(hid_t):: plist_id
  integer(hsize_t), dimension(3):: start,totaldims,filedims,filemaxdims
  integer(hsize_t), dimension(3):: cdims,nooffset
  integer, dimension(size):: lastdims
  integer:: mpierr
  
  integer:: i,rank,lastdim
  integer, dimension(MPI_STATUS_SIZE):: status
    
  cdims = dims
  start = 0
  nooffset = 0
  totaldims = dims
  
  lastdim = dims(3) ! Don't mess with ints and longs
  
  call MPI_ALLGATHER(lastdim,1,MPI_INTEGER,lastdims,1,MPI_INTEGER,comm,mpierr)
  
  totaldims(3) = sum(lastdims)

  call mpi_comm_rank(comm,rank,mpierr)
  if (rank == 0) write(*,*) "totaldims", totaldims
  
  if (rank == 0) then
     !Open the global dataset and get the global dataspace
     call h5dopen_f(fid,name,dset,ierr)
     call h5dget_space_f(dset,dspace,ierr)
     call h5sget_simple_extent_dims_f(dspace, filedims, filemaxdims, ierr)
     
     ! write(*,*) "INFO: Loading file using the serial interface"
     ! write(*,'(a20,3i5)') "file dimensions:", filedims
  endif
  
  do i=size-1,1,-1
     cdims(3) = lastdims(i+1)
     if (rank == i) then
        call mpi_recv(data,product(cdims),MPI_REAL,0,0,comm,status,ierr)
     end if
     
     if (rank == 0) then
        !Create the local dataset
        call h5screate_simple_f(3,cdims,mspace,ierr)
        call h5sselect_hyperslab_f(mspace,H5S_SELECT_SET_F,nooffset,cdims,ierr)
        call h5sselect_hyperslab_f(dspace,H5S_SELECT_SET_F,offset+start,cdims,ierr)   
        
        !Select the hyperslab in the global dataset
        start(3) = sum(lastdims(1:i+1))-lastdims(i+1)
        ! write(*,*) "***"
        ! write(*,'(i3,a7,3i5)') i,"start",offset+start
        ! write(*,'(i3,a7,3i5)') i,"count",cdims
        ! write(*,*) "***"
        
        !Commit the memspace to the disk
        call h5dread_f(dset,H5T_NATIVE_REAL,data,cdims,ierr,mspace,dspace,H5P_DEFAULT_F)
        
        ! write(*,'(a,i3,i12)') "Sending data to process #:", i, product(cdims)
        call mpi_send(data,product(cdims),MPI_REAL,i,0,comm,ierr)
        
        call h5sclose_f(mspace,ierr)
     end if
     
     call mpi_barrier(comm,ierr)
  end do
  
  
  if (rank == 0) then
     write(*,*) "My own rank, do not send data"
     ! Read the first part for the master
     call h5screate_simple_f(3,dims,mspace,ierr)
     call h5sselect_hyperslab_f(mspace,H5S_SELECT_SET_F,nooffset,dims,ierr)
     ! Not compatible with non zero offset
     start(3) = 0
     call h5sselect_hyperslab_f(dspace,H5S_SELECT_SET_F,offset+start,dims,ierr)
     call h5dread_f(dset,H5T_NATIVE_REAL,data,dims,ierr,mspace,dspace,H5P_DEFAULT_F)
     call h5sclose_f(mspace,ierr)
     
     !Close datasets and global dataspace
     call h5dclose_f(dset,ierr)   
     call h5sclose_f(dspace,ierr)
  end if

end subroutine h5load_serial


subroutine readheader(filename, nx, ny, nz2)    
  use alloc_dns,only: tiempo,y
  use genmod,only:um,timeinit

  use h5lt

  implicit none
  character(len = 256), intent(in):: filename

  real(kind = 8):: cfl,re,dt
  real(kind = 8):: lx,ly,lz
  !     integer, intent(out):: lx,ly,lz
  integer, intent(out):: nx,ny,nz2
  integer:: xout    
  integer:: procs
  integer*8:: cursor,i
  character(len=1):: field

  integer:: h5err
  integer(HID_T):: fid
  integer(HSIZE_T), dimension(1):: hdims
  real(kind=8), dimension(1):: aux
  integer, dimension(1):: iaux

  write(*,*) 'LEYENDO DE.............', trim(filename)//".h5"

  call H5Fopen_f(trim(filename)//".h5",H5F_ACC_RDONLY_F,fid,h5err)

  call H5LTread_dataset_string_f(fid,"Variable",field,h5err)
  hdims = (/ 1 /)
  call H5LTread_dataset_double_f_1(fid,"tiempo",aux,hdims,h5err)
  tiempo = aux(1)

  call H5LTread_dataset_double_f_1(fid,"cfl",aux,hdims,h5err)
  cfl = aux(1)

  call H5LTread_dataset_double_f_1(fid,"Re",aux,hdims,h5err)
  re = aux(1)

  call H5LTread_dataset_double_f_1(fid,"lx",aux,hdims,h5err)
  lx = aux(1)

  call H5LTread_dataset_double_f_1(fid,"ly",aux,hdims,h5err)
  ly = aux(1)

  call H5LTread_dataset_double_f_1(fid,"lz",aux,hdims,h5err)
  lz = aux(1)

  call H5LTread_dataset_int_f_1(fid,"nx",iaux,hdims,h5err)
  nx = iaux(1)

  call H5LTread_dataset_int_f_1(fid,"ny",iaux,hdims,h5err)
  ny = iaux(1)

  call H5LTread_dataset_int_f_1(fid,"nz2",iaux,hdims,h5err)
  nz2 = iaux(1)

  call H5LTread_dataset_int_f_1(fid,"xout",iaux,hdims,h5err)
  xout = iaux(1)

  call H5LTread_dataset_double_f_1(fid,"timeinit",aux,hdims,h5err)
  timeinit = aux(1)

  call H5LTread_dataset_double_f_1(fid,"dt",aux,hdims,h5err)
  dt = aux(1)

  hdims = (/ ny+2 /)
  call H5LTread_dataset_double_f_1(fid,"y",y,hdims,h5err)
  hdims = (/ ny+1 /)
  call H5LTread_dataset_double_f_1(fid,"um",um,hdims,h5err)

  call H5Fclose_f(fid,h5err)


  write(*,*) "field ", field
  write(*,*) "tiempo", tiempo
  write(*,*) "cfl", cfl
  write(*,*) "re", re
  write(*,*) "lx", lx
  write(*,*) "ly", ly
  write(*,*) "lz", lz
  write(*,*) "nxr", nx
  write(*,*) "nyr", ny
  write(*,*) "nz2r", nz2
  write(*,*) "xout", xout
  write(*,*) "timeinit", timeinit
  write(*,*) "dt", dt
  write(*,*) "y", y(1:3), "...", y(ny:ny+2)
  write(*,*) "um", um(1:3), "...", um(ny-1:ny+1)


end subroutine readheader




!============================================================
!============================================================
!============================================================

#ifdef CREATEPROFILES
subroutine create_profiles(ut,vt,wt,rthin,mpiid,communicator)
  use alloc_dns,only: re,pi,ax,y,dy,idy,idx,inyv,cofivy,inby,vmagic
  use point
  use ctesp
  implicit none
  include "mpif.h"
  integer,intent(in)::communicator
  real*8,dimension(nz1,ny,ib:ie)  :: vt
  real*8,dimension(nz1,ny+1,ib:ie):: ut,wt
  real*8,dimension(nx)::x,dstar,reth,uep,utau,drota,Hmon,redels
  real*8,dimension(:,:),allocatable:: u_composite,v_composite,dudx,buffer,buffer2
  real*8,dimension(:,:),allocatable:: u_inner,u_log,u_outer
  real*8,dimension(ny+1):: eta,yplus,uinnerp,ulogp,Exp1,wouterp,uinfp,uouterp,ucomp,ucompi,bf
  real*8 e1,c1,ei1,kap,ckap,cprim,rd,d1,ee1,ee2,ee3,ee4,ee5,eulcns
  real*8 rx,dx,rthin,w0,w1,w2,w8,offset
  integer i,j,mpiid,dot,ierr,status(MPI_STATUS_SIZE)
  real*8:: yint(0:ny+1),f_blending(nx)


  !Every node allocate the buffer:
  allocate(buffer(1:ny+1,2),buffer2(1:ny+1,2));
  buffer=0d0;buffer2=0d0    
  !Every node allocate the array for U0 & V0:
  allocate(u0c(1:ny+1,ib:ie),v0c(1:ny+1,ib:ie));
  u0c=0d0;v0c=0d0   
  allocate(u0c_once(1:ny+1,ib:ie),w0c_once(1:ny+1,ib:ie),v0c_once(1:ny+1,ib:ie));
  u0c_once=0d0;v0c_once=0d0;w0c_once=0d0

  if(mpiid.eq.0) then
     write(*,*) 'VALORES INICIALES: Rtheta_in:',rthin,'Num_planes=',num_planes
     allocate(u_composite(ny+1,nx),v_composite(ny,nx),dudx(ny,nx))       

     u_composite=0d0;v_composite=0d0;dudx=0d0
     uinnerp=0d0;ulogp=0d0;Exp1=0d0;wouterp=0d0;uinfp=0d0;uouterp=0d0
     ucomp=0d0;ucompi=0d0
     x=0d0;dstar=0d0;reth=0d0;uep=0d0;
     eta=0d0;yplus=0d0

     !CONSTANTS FOR THE FITTINGS 
     e1=0.8659d0; c1=0.01277d0;   !!reth=c1*rex^e1
     ei1=1d0/e1
     kap=0.384d0; ckap=4.17d0!;ckap=4.127d0;   !! uep=log(reth)/kap+ckap 
     cprim=7.135d0              
     dx=ax*pi/(nx-1)
     !CONSTANTS FOR THE COMPOUNDED PROFILE
     d1=4.17d0;
     eulcns=0.57721566d0;
     ee1=0.99999193d0;ee2=0.24991055d0;ee3=0.05519968d0;
     ee4=0.00976004d0;ee5=0.00107857d0;
     w0=0.6332d0;w1=-0.096d0;
     w2=28.5d0;  w8=33000d0;

     yint(0:ny)=(y(0:ny)+y(1:ny+1))*0.5d0 !Interpolate grid Y to U position
     yint(ny+1)=2*yint(ny)-yint(ny-1)

     !CREATING THE PROFILES
     do i=1,nx
        !Computing X grid --> Re_x --> Re_theta --> Uinf+ --> u_tau --> H --> delta_star --> delta_rota 
        x(i)=dx*(i-1)
        reth(i)=(rthin**ei1+c1**ei1*re*x(i)*Uinfinity)**e1           
        Hmon(i)=1d0+2.7302d0/log(reth(i))+3.9945d0/log(reth(i))**2&
             &          -1.6102d0/log(reth(i))**3-13.9915d0/log(reth(i))**4&
             &          -1.4920d0/log(reth(i))**5+63.9554d0/log(reth(i))**6     !Eq(21) H=H(Re_theta)         

        dstar(i)=reth(i)*Hmon(i)/(re*Uinfinity)
        redels(i)=dstar(i)*Uinfinity*re !Re_delta_star         
        !============================================================= 
        uinfp(:)=1/kap*log(dstar(i)*re*Uinfinity)+3.30d0   !Eq(11)          
        utau(i)=Uinfinity/uinfp(i)
        drota(i)=uinfp(i)*dstar(i)
        eta(1:ny+1)=yint(1:ny+1)/drota(i)          
        !=============================================================                    
        yplus(1:ny+1)=yint(1:ny+1)*re*utau(i)

        if(i.eq.30) then
           write(*,*) '=======Composite Profiles: VALUES @ i=30 =================='
           write(*,*) 'x',x(i),'dx',dx
           write(*,*) 'reth(i)',reth(i)
           write(*,*) 'uep(i)',uinfp(i)
           write(*,*) 'dstar(i)',dstar(i)
           write(*,*) 'Re_theta_star(i)',redels(i)
           write(*,*) 'drota(i)',drota(i) 
           write(*,*) '==========================================================='             
        endif

        !==============Composing the profiles===============
        !INNER REGION------------------------------------------
        uinnerp(:)=0.68285472*log(yplus(:)**2 +4.7673096*yplus(:) +9545.9963)+&
             &     1.2408249*atan(0.010238083*yplus(:)+0.024404056)+&
             &     1.2384572*log(yplus(:)+95.232690)-11.930683-&
             &     0.50435126*log(yplus(:)**2-7.8796955*yplus(:)+78.389178)+&
             &     4.7413546*atan(0.12612158*yplus(:)-0.49689982)&
             &    -2.7768771*log(yplus(:)**2+16.209175*yplus(:)+933.16587)+&
             &     0.37625729*atan(0.033952353*yplus(:)+0.27516982)+&
             &     6.5624567*log(yplus(:)+13.670520)+6.1128254   !Eq(6)            

        !LOG PART ------------------------------------------
        ulogp(:)=1d0/kap*log(yplus(:))+d1            
        !Blending function: (to avoid the overshoot in the composed profile)
        bf(:)=(1-tanh((eta(:)-0.04d0)/0.01d0))/2d0;
        uinnerp(:)=bf(:)*uinnerp(:)+(1-bf(:))*ulogp(:)          
        !OUTER REGION------------------------------------------
        Exp1(:)=-eulcns-log(eta(:))+ee1*eta(:)-ee2*eta(:)**2+&
             &       ee3*eta(:)**3-ee4*eta(:)**4+ee5*eta(:)**5   !Eq(8)
        wouterp(:)=(1/kap*Exp1(:)+w0)*0.5d0*(1-tanh(w1/eta(:)+w2*eta(:)**2+w8*eta(:)**8)) !Eq(9)           
        !Matching---------------------------------------------          
        uouterp(:)=uinfp(:)-wouterp(:)         
        !Composed profile:
        ucomp(2:ny+1)=uinnerp(1:ny)*uouterp(1:ny)/ulogp(1:ny)         
        ucomp(1)=-1d0/inby(2,1)*(inby(2,2)*ucomp(2)+inby(2,3)*ucomp(3)+inby(2,4)*ucomp(4)); !BC u(1) Pade Scheme

        if(i.eq.30) write(*,*) 'u@wall: pade, linear',ucomp(1),y(0)/y(2)*ucomp(2)
        !Value at the ghost cell
        u_composite(:,i)=ucomp(:)*utau(i)                                              
        u_composite(ny+1,i)=u_composite(ny,i)  !Adding ny+1 point            

        if(i.eq.30) then          
           write(*,*) 'Ucomposite Value @i=30... j=1:3 and j=ny-2:ny'
           do j=1,3;write(*,*) u_composite(j,i);enddo	  
              do j=ny-2,ny;write(*,*) u_composite(j,i);enddo
              endif
           enddo

           !Deriving the V0 composite profile:
           v_composite(1,:)=0d0 !Initial Condition       
           do j=1,ny-1
              do i=2,nx
                 dudx(j,i)=(u_composite(j+1,i)-u_composite(j+1,i-1))*idx !dudx @ (i,j) as computed at Poison                                          
              enddo
           enddo
           do i=2,nx
              do j=1,ny-1
                 v_composite(j+1,i)=v_composite(j,i)-dudx(j,i)/idy(j)            
              enddo
           enddo
           v_composite(:,1)=v_composite(:,2) !That profile is not available,so I copy it.
           !Changing Top Boundary Condition for Vtop              
           vmagic(1:nx)=v_composite(ny,1:nx)  !Setting the new Vmagic in order to avoid any discontinuity
        endif


        !Blending function to transition from the old to the new profiles: tanh(X-X0); X0=NUM_PLANES+150                                                
        do i=1,nx;        
           f_blending(i)=(1d0-tanh((i-(num_planes+150))/45d0))*0.5d0
        enddo

        if(mpiid.eq.0) then      
           write(*,*) 'START SENDING MEAN PROFILES TO NODES:'
           !===================Send Info to other nodes============================
           !Node #0 copy its data
           do i=ib,ie  
              if(i.le.num_planes) then
                 u0c(1:ny+1,i)=u_composite(1:ny+1,i)
                 v0c(1:ny,i)  =v_composite(1:ny  ,i)          
              endif
              !Transition between the new profiles and the old profiles (done only once here...not imposed anymore)             
              u0c_once(1:ny+1,i)=f_blending(i)*u_composite(1:ny+1,i)+(1d0-f_blending(i))*ut(1,1:ny+1,i)
              v0c_once(1:ny,i)  =f_blending(i)*v_composite(1:ny  ,i)+(1d0-f_blending(i))*vt(1,1:ny  ,i)
              w0c_once(1:ny+1,i)=(1d0-f_blending(i))*wt(1,1:ny+1  ,i)             
           enddo

           !Sending U0 and V0 to the nodes:
           write(*,*) 'Sending the composite profiles U0 & V0'
           do dot = 1,nummpi-1       
              do i= ibeg(dot),iend(dot)
                 if(i.le.num_planes) then
                    buffer(1:ny+1,1)=u_composite(1:ny+1,i)
                    buffer(1:ny  ,2)=v_composite(1:ny  ,i)   
                    call MPI_SEND(buffer,size(buffer),MPI_real8,dot,1,communicator,ierr)             
                 endif
                 buffer2(1:ny+1,1)=f_blending(i)*u_composite(1:ny+1,i)
                 buffer2(1:ny  ,2)=f_blending(i)*v_composite(1:ny  ,i)
                 call MPI_SEND(buffer2,size(buffer2),MPI_real8,dot,2,communicator,ierr) 
              enddo
           enddo
           write(*,*) 'Sending the composite profiles U0 & V0...... DONE';
           write(*,*) '===========================================================' 
           write(*,*)
           !Node #0 free the memory:
           deallocate(u_composite,v_composite,dudx)
        else
           !Receiving the U0 & V0 profiles:      
           do i=ib,ie
              if(i.le.num_planes) then
                 call MPI_RECV(buffer,size(buffer),MPI_real8,0,1,communicator,status,ierr)
                 u0c(1:ny+1,i)=buffer(1:ny+1,1)
                 v0c(1:ny,i)  =buffer(1:ny  ,2)   
              endif
              call MPI_RECV(buffer2,size(buffer2),MPI_real8,0,2,communicator,status,ierr)
              u0c_once(1:ny+1,i)=buffer2(1:ny+1,1)+(1d0-f_blending(i))*ut(1,1:ny+1,i)
              v0c_once(1:ny  ,i)=buffer2(1:ny  ,2)+(1d0-f_blending(i))*vt(1,1:ny  ,i)      
              w0c_once(1:ny+1,i)=(1d0-f_blending(i))*wt(1,1:ny+1,i)
           enddo
        endif

        if(mpiid.eq.0) write(*,*) 'Broadcasting New Vmagic.....'
        call MPI_BCAST(vmagic,nx,MPI_REAL8,0,communicator,ierr) !Broadcasting Vmagic
        deallocate(buffer,buffer2)
      endsubroutine create_profiles


      !===========================================================================================
      !===========================================================================================
      !===========================================================================================

      subroutine impose_profiles(ut,vt,wt,mpiid,communicator)
        use point
        use ctesp
        implicit none
        include "mpif.h"
        integer,intent(in)::communicator
        complex*16,dimension(0:nz2,ny+1,ib:ie)::ut,wt
        complex*16,dimension(0:nz2,ny  ,ib:ie)::vt
        integer:: i,ierr,status(MPI_STATUS_SIZE),mpiid
        !----------------------------------WRITING THE K=0 XY PLANE  TO A FILE-------------------
        paso=paso+1
        if(paso.eq.1) then
           if(mpiid.eq.0) write(*,*) 'WRITING THE K=0 XY PLANE TO A FILE FOR U,V & W before POISON'
           do i=ib,ie   
              pdiv(1:ny,i)=real(ut(0,1:ny,i),kind=8) !Each node copy a piece of the array
           enddo
           call MPI_ALLREDUCE(MPI_IN_PLACE,pdiv,ny*nx,MPI_real8,MPI_SUM,communicator,ierr)      
           if(mpiid.eq.0) write(28) pdiv(1:ny,1:nx)
           pdiv=0d0

           do i=ib,ie   
              pdiv(1:ny,i)=real(vt(0,1:ny,i),kind=8) !Each node copy a piece of the array
           enddo
           call MPI_ALLREDUCE(MPI_IN_PLACE,pdiv,ny*nx,MPI_real8,MPI_SUM,communicator,ierr)
           if(mpiid.eq.0) write(28) pdiv(1:ny,1:nx)      
           pdiv=0d0

           do i=ib,ie   
              pdiv(1:ny,i)=real(wt(0,1:ny,i),kind=8) !Each node copy a piece of the array
           enddo
           call MPI_ALLREDUCE(MPI_IN_PLACE,pdiv,ny*nx,MPI_real8,MPI_SUM,communicator,ierr)      
           if(mpiid.eq.0) write(28) pdiv(1:ny,1:nx)
           pdiv=0d0
           if(mpiid.eq.0) write(*,*) 'WRITING THE K=0 XY PLANE TO A FILE FOR U,V & W before POISON.............DONE'
        endif

        !----------------------------    
        if(paso.eq.0) then
           if(mpiid.eq.0) write(*,*) 'Imponiendo el El perfil especial'
           do i=ib,ie       
              ut(0,1:ny+1,i)=u0c_once(1:ny+1,i)   !The imaginary part is then set to 0
              vt(0,1:ny  ,i)=v0c_once(1:ny  ,i) 
              wt(0,1:ny+1,i)=w0c_once(1:ny+1,i)                    
           enddo
        else
           do i=ib,ie
              if(i.le.num_planes) then
                 ut(0,1:ny+1,i)=u0c(1:ny+1,i)   !The imaginary part is then set to 0
                 vt(0,1:ny  ,i)=v0c(1:ny  ,i) 
                 wt(0,1:ny+1,i)=0d0                   
              endif
           enddo
        endif
      endsubroutine impose_profiles


      !===========================================================================

      subroutine check_divergence(ut,vt,wt,rest,mpiid,communicator)
        use point
        use alloc_dns,only:idx,idy,idxx,idyy,phiy,dy,y,kaz,kaz2,kmod,ayp
        use ctesp
        use omp_lib
        use temporal
        implicit none
        include 'mpif.h'

        ! ---------------------- I/O -------------------------------------!
        integer mpiid
        integer,intent(in)::communicator
        complex*16, dimension(0:nz2,ny+1,ib:ie):: wt,ut
        complex*16, dimension(0:nz2,ny,ib:ie)  :: pt,vt,rest
        complex*16, dimension(0:nz2,ny+1)  :: rt
        ! -------------------------- Work Arrays -------------------------!
        real*8  aypr(3,ny-1)
        integer i,j,l,k,kk,k2
        ! --------------------- MPI workspaces -----------------------------!
        integer istat(MPI_STATUS_SIZE),ierr,comm,countu,countv,tipo
        ! ----------------------------------------------------------------!
        countu=(nz2+1)*(ny+1)
        countv=(nz2+1)*ny
        comm = communicator
        tipo=MPI_COMPLEX16

        ! --- compute the divergence, we are in (zy) 
        do i=ib0,ie
           !$OMP PARALLEL DO DEFAULT(SHARED) PRIVATE(j) SCHEDULE(STATIC)
           do j=1,ny-1
              rest(:,j,i) = wt(:,j+1,i)*kaz +(vt(:,j+1,i)-vt(:,j,i))*idy(j)
           enddo
        enddo
        ! --- add du/dx -------------
        do i=ib+1,ie
           !$OMP PARALLEL DO DEFAULT(SHARED) PRIVATE(j) SCHEDULE(STATIC)
           do j=1,ny-1
              rest(:,j,i)=rest(:,j,i)+idx*(ut(:,j+1,i)-ut(:,j+1,i-1))
           enddo
        enddo

        if (mpiid.eq.0) then
           call MPI_SEND(ut(0,1,ie),countu,tipo,mpiid+1,0,comm,istat,ierr)
        elseif (mpiid.eq.pnodes-1) then
           call MPI_RECV(rt,countu,tipo,mpiid-1,0,comm,istat,ierr)
           !$OMP PARALLEL DO DEFAULT(SHARED) PRIVATE(j) SCHEDULE(STATIC)
           do j=1,ny-1
              rest(:,j,ib)=rest(:,j,ib)+idx*(ut(:,j+1,ib)-rt(:,j+1))
           enddo
        else
           call MPI_SENDRECV(ut(0,1,ie),countu,tipo,mpiid+1,0,  &
                &                      rt,countu,tipo,mpiid-1,0,  comm,istat,ierr)
           !$OMP PARALLEL DO DEFAULT(SHARED) PRIVATE(j) SCHEDULE(STATIC)
           do j=1,ny-1
              rest(:,j,ib)=rest(:,j,ib)+idx*(ut(:,j+1,ib)-rt(:,j+1))
           enddo
        endif

        !=========================================
        do i=ib0,ie   
           pdiv(1:ny-1,i)=real(rest(0,1:ny-1,i),kind=8) !Each node copy a piece of the array
        enddo
        call MPI_ALLREDUCE(pdiv(1:ny-1,1:nx),pdiv(1:ny-1,1:nx),(ny-1)*nx,MPI_real8,MPI_SUM,communicator,ierr)
        if(mpiid.eq.0) then
           write(*,*) 'ESCRIBIENDO LA DIVERGENCIA INICIAL DEL CAMPO:'
           write(27) pdiv(1:ny-1,1:nx)
           write(*,*) 'Div(i,30)='
           do i=20,30;write(*,*) pdiv(i,30);enddo
              write(*,*) '-------------------------------------------------'
              write(*,*) 'Div(i,600)='
              do i=20,30;write(*,*) pdiv(i,600);enddo
                 write(*,*) '                     			.............DONE'
              endif
              pdiv=0d0
              !=========================================
            endsubroutine check_divergence
#endif



