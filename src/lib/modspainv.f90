!> Module containing subroutines for sparse inverses of symmetric positive definite matrices

!> @todo Still raw and not very efficient

!Based on Karin Meyer 's code !(didgeridoo.une.edu.au/womwiki/doku.php?id=fortran:fortran)
!Slightly rewritten for my purposes

module modspainv
#if (_DP==0)
 use iso_fortran_env,only:output_unit,int32,int64,real32,real64,wp=>real32
#else
 use iso_fortran_env,only:output_unit,int32,int64,real32,real64,wp=>real64
#endif
 !$ use omp_lib
 implicit none
 private
 public::get_ichol,get_spainv

 integer(kind=int32)::minsizesupernode=256

 interface get_ichol
  module procedure get_ichol_crs
 end interface

 interface get_spainv
  module procedure get_spainv_crs
 end interface

 interface
  subroutine smbfct(neqns,xadj,adjncy,perm,invp,&
              xlnz,maxlnz,xnzsub,nzsub,maxsub,&
              rchlnk,mrglnk,marker,flag&
              )
   integer,intent(in)::neqns
   integer::maxsub,flag,maxlnz
   integer,intent(in)::xadj(*),adjncy(*)
   integer,intent(in)::perm(*),invp(*)
   integer::xlnz(*),xnzsub(*),nzsub(*),rchlnk(*),mrglnk(*),marker(*)
  end subroutine
 end interface

contains

!PUBLIC
subroutine get_ichol_crs(ia,ja,a,xadj,adjncy,perm,un)
 integer(kind=int32),intent(in)::ia(:)
 integer(kind=int32),intent(in)::ja(:)
 integer(kind=int32),intent(inout)::xadj(:),adjncy(:)
 integer(kind=int32),intent(inout)::perm(:)  !Ap(i,:)=A(perm(i),:)
 integer(kind=int32),intent(in),optional::un
 real(kind=wp),intent(inout)::a(:)
 
 integer(kind=int32)::unlog,neqns
 real(kind=real64)::time(6)

 unlog=output_unit
 if(present(un))unlog=un

 neqns=size(ia)-1

 call get_ichol_spainv_crs(neqns,ia,ja,a,xadj,adjncy,perm,.false.,time)

 call writetime(unlog,time,'CHOL FACT.')

end subroutine

subroutine get_spainv_crs(ia,ja,a,xadj,adjncy,perm,un)
 integer(kind=int32),intent(in)::ia(:)
 integer(kind=int32),intent(in)::ja(:)
 integer(kind=int32),intent(inout)::xadj(:),adjncy(:)
 integer(kind=int32),intent(inout)::perm(:)  !Ap(i,:)=A(perm(i),:)
 integer(kind=int32),intent(in),optional::un
 real(kind=wp),intent(inout)::a(:)
 
 integer(kind=int32)::unlog,neqns
 real(kind=real64)::time(6)

 unlog=output_unit
 if(present(un))unlog=un

 neqns=size(ia)-1

 call get_ichol_spainv_crs(neqns,ia,ja,a,xadj,adjncy,perm,.true.,time)

 call writetime(unlog,time,'INVERSION')

end subroutine

subroutine get_ichol_spainv_crs(neqns,ia,ja,a,xadj,adjncy,perm,lspainv,time)
 integer(kind=int32),intent(in)::neqns
 integer(kind=int32),intent(in)::ia(:)
 integer(kind=int32),intent(in)::ja(:)
 integer(kind=int32),intent(inout)::xadj(:),adjncy(:)
 integer(kind=int32),intent(inout)::perm(:)  !Ap(i,:)=A(perm(i),:)
 real(kind=wp),intent(inout)::a(:)
 real(kind=real64),intent(inout)::time(:)
 logical,intent(in)::lspainv
 
 integer(kind=int32)::i
 integer(kind=int32)::nnode
 integer(kind=int32)::maxsub,flag,maxlnz
 integer(kind=int32),allocatable::xlnz(:),xnzsub(:),nzsub(:)
 integer(kind=int32),allocatable::inode(:)
 real(kind=wp),allocatable::xspars(:),diag(:)
 !$ real(kind=real64)::t1

 !symbolic factorization
 !$ t1=omp_get_wtime()
 call symbolicfact(neqns,ia(neqns+1)-1,xadj,adjncy,perm,xlnz,maxlnz,xnzsub,nzsub,maxsub,flag)
 !$ time(1)=omp_get_wtime()-t1
 !$ t1=omp_get_wtime()

 call computexsparsdiag(neqns,ia,ja,a,xlnz,nzsub,xnzsub,maxlnz,xspars,diag,perm)
 !$ time(2)=omp_get_wtime()-t1
 !$ t1=omp_get_wtime()

 !super following Karin Meyer
 allocate(inode(neqns))
 call super_nodes(neqns,xlnz,xnzsub,nzsub,nnode,inode)
 !$ time(3)=omp_get_wtime()-t1
 !$ t1=omp_get_wtime()

 ! Cholesky factorization
 call super_gsfct(neqns,xlnz,xspars,xnzsub,nzsub,diag,nnode,inode)
 !$ time(4)=omp_get_wtime()-t1
 !$ t1=omp_get_wtime()

 if(lspainv)then
  ! Matrix inverse
  call super_sparsinv(neqns,xlnz,xspars,xnzsub,nzsub,diag,nnode,inode)
  !$ time(5)=omp_get_wtime()-t1
  !$ t1=omp_get_wtime()
 endif
 
 !Convert to ija
 call converttoija(neqns,xlnz,xspars,xnzsub,nzsub,diag,ia,ja,a,perm)
 !$ time(6)=omp_get_wtime()-t1
 !$ t1=omp_get_wtime()

#if (_VERBOSE >1)
 write(*,'(2x,a,i0)')'Flag symbolic factorization : ',flag
 write(*,'(2x,a,i0)')'Number of super-nodes       : ',nnode
 maxsub=0
 do i=1,nnode
  maxsub=max(maxsub,inode(i)-inode(i+1)+1)
  write(*,'(1x,4(a,i8))') 'node',i,' from row', inode(i+1)+1,'  to row', inode(i),' size ',inode(i)-inode(i+1)
 end do
 write(*,'(2x,a,i0/)')'Max size of super-nodes     : ',maxsub
#endif

end subroutine


!PRIVATE
subroutine symbolicfact(neqns,nnzeros,xadj,adjncy,perm,xlnz,maxlnz,xnzsub,nzsub,maxsub,flag)
 integer(kind=int32),intent(in)::neqns,nnzeros
 integer(kind=int32),intent(in)::xadj(:),adjncy(:),perm(:)
 integer(kind=int32),intent(out)::maxlnz,maxsub,flag
 integer(kind=int32),allocatable,intent(out)::xlnz(:),xnzsub(:),nzsub(:)

 integer(kind=int32)::i,maxsubinit
 integer(kind=int32),allocatable::invp(:),rchlnk(:),mrglnk(:),marker(:)

 allocate(invp(size(perm)))
 do i=1,size(perm)
  invp(perm(i))=i
 enddo

 allocate(xlnz(neqns+1),xnzsub(neqns+1))
 allocate(rchlnk(neqns),mrglnk(neqns),marker(neqns))
 xlnz=0
 xnzsub=0
 rchlnk=0
 mrglnk=0
 marker=0
 !maxsub=ia(neqns+1)-1
 maxsub=nnzeros

 do
  flag=0
  maxsubinit=maxsub
  if(allocated(nzsub))deallocate(nzsub)
  allocate(nzsub(maxsub))
  nzsub=0
  call smbfct(neqns,xadj,adjncy,perm,invp,xlnz,maxlnz,xnzsub,nzsub,maxsub,&
              rchlnk,mrglnk,marker,flag&
              )
  if(maxsub.ne.maxsubinit)cycle
  if(flag.eq.0)exit
  maxsub=maxsub*2
 enddo
 deallocate(rchlnk,mrglnk,marker)

end subroutine

subroutine super_nodes( neqns, xlnz, xnzsub, ixsub, nnode, inode )
 integer(kind=int32),intent(in)::neqns
 integer(kind=int32),intent(in)::ixsub(:),xlnz(:),xnzsub(:)
 integer(kind=int32),intent(out)::nnode
 integer(kind=int32),intent(out)::inode(:) !size=neqns

 integer(kind=int32)::i,ii,j,n,ilast,kk
 real(kind=wp)::xx

 ! establish boundaries between diaggonal blocks 100% full
 ilast = neqns
 nnode = 0
 do i = neqns-1, 1, -1
    ii = xnzsub(i)
    n = 0
    do j = xlnz(i), xlnz(i+1)-1
       kk = ixsub(ii)
       ii = ii + 1
       if(  kk > ilast ) exit
       n = n + 1
    end do
    xx = dble( n ) / dble( ilast - i )
    if( xx < 1._wp .and. (ilast-i)>minsizesupernode ) then
     nnode = nnode +1
     inode(nnode) = ilast
     ilast = i
    end if
 end do
 nnode = nnode +1
 inode(nnode) = ilast
 inode(nnode+1) = 0

end subroutine 

subroutine super_gsfct(neqns,xlnz,xspars,xnzsub,ixsub,diag,nnode,inode)
 integer(kind=int32),intent(in)::neqns,nnode
 integer(kind=int32),intent(in)::ixsub(:),xlnz(:),xnzsub(:),inode(:)
 real(kind=wp),intent(inout)::xspars(:),diag(:)

 integer(kind=int32)::i,j,k,jrow,n,ksub,irow,jnode,icol1,icol2,jcol,ii,jj,mm,kk
 integer(kind=int32),allocatable::jvec(:),kvec(:)
 real(kind=wp),allocatable::ttt(:,:),s21(:,:),s22(:,:)

 allocate(jvec(neqns),kvec(neqns),stat=ii)
 if( ii /= 0 ) call alloc_err

 do jnode = nnode, 1, -1
  icol1 = inode(jnode+1) + 1
  icol2 = inode(jnode)
  mm = icol2 - icol1 +1

  !pick out diagonal block
  allocate( ttt(icol1:icol2,icol1:icol2), stat = ii )
  if( ii /= 0 ) call alloc_err
  ttt=0.d0
  jvec=0
  n=0
  do irow = icol1, icol2
   ttt(irow,irow) = diag(irow)
   ksub = xnzsub(irow)
   do i = xlnz(irow), xlnz(irow+1)-1
    jcol = ixsub(ksub)
    ksub = ksub + 1
    if( jcol <= icol2 ) then
     ttt(jcol,irow) = xspars(i) 
    else
     if(jvec(jcol).eq.0)then
      n=n+1
      jvec(jcol)=n
      kvec(n)=jcol
     endif
    end if
   end do
  end do

  !factorise
  call dpotrf( 'L', mm, ttt, mm, ii )
  if( ii /= 0 ) then
   write(*,*)'Dense fact: Routine DPOTRF returned error code', ii
   write(*,*)'... coefficient matrix must be positive definite'
   error stop
  end if

  !adjust block below diagonal
     if( n > 0 ) then
         !... pick out rows
         allocate( s21(n, icol1:icol2), stat = ii )
         if( ii /= 0 ) call alloc_err
         s21 = 0.d0
         do irow = icol1, icol2
            ksub = xnzsub(irow)
            do i = xlnz(irow), xlnz(irow+1)-1
               jcol = ixsub(ksub)
               ksub = ksub + 1
               if( jcol <= icol2 ) cycle
               jj = jvec(jcol)
               s21(jj,irow) = xspars(i)
            end do
         end do

         !calculate L21
         call dtrsm( 'R', 'L', 'T', 'N', n, mm, 1.d0, ttt, mm, s21, n )

         !adjust remaining triangle to right: A22 := A22 - L21 L21'
         allocate( s22(n,n), stat = ii )
         if( ii /= 0 ) call alloc_err
         call dsyrk( 'L', 'N', n, mm, 1.d0, s21, n, 0.d0, s22, n )
         kk = maxval(kvec(1:n))
         do i = 1, n
             jrow = kvec(i)
             diag(jrow) = diag(jrow) - s22(i,i)
             ksub = xnzsub(jrow)
             do j = xlnz(jrow), xlnz(jrow+1)-1
                jcol = ixsub(ksub)
                if( jcol > kk ) exit
                ksub = ksub + 1
                ii = jvec(jcol)
                if( ii > 0 ) then
                 if(ii>i)then
                  xspars(j) = xspars(j) - s22(ii,i)
                 else
                  xspars(j) = xspars(j) - s22(i,ii)
                 endif
                endif
             end do
         end do
         deallocate( s22 )
     end if

     !transfer block back to sparse storage
     do irow = icol1, icol2 
       diag(irow) = ttt(irow,irow)
        ksub = xnzsub(irow)
        do i = xlnz(irow), xlnz(irow+1)-1
           jcol = ixsub(ksub)
           ksub = ksub + 1
           if( jcol <= icol2 ) then
               xspars(i) = ttt(jcol,irow)
           else
               xspars(i) = s21( jvec(jcol), irow)
           end if
        end do
     end do
     deallocate( ttt )
     if( n > 0 ) deallocate( s21)

 end do ! jnode

 deallocate( jvec, kvec )

end subroutine

subroutine super_sparsinv(neqns,xlnz,xspars,xnzsub,ixsub,diag,nnode,inode)
  integer(kind=int32),intent(in)::neqns,nnode
  integer(kind=int32),intent(in)::ixsub(:),xlnz(:),xnzsub(:),inode(:)
  real(kind=wp),intent(inout) ::xspars(:),diag(:)

  integer(kind=int32)::irow,ksub,i,j,k,m,jcol,jrow, jnode, icol2, icol1, ii,jj, mm, n21, iopt
  integer(kind=int32),allocatable::kvec(:),jvec(:)
  real(kind=wp)::tt,xx
  real(kind=wp),dimension(:,:),allocatable:: ttt, s21, s22, f21
  real(kind=wp),dimension(:),allocatable:: rr, qx

  allocate( jvec(neqns), kvec(neqns),stat = ii )
  if( ii /= 0 ) call alloc_err

! backwards flops: determine inverse using supernodal blocks
  do jnode = 1, nnode
     icol1 = inode(jnode+1) + 1
     icol2 = inode(jnode)
     mm = icol2 - icol1 +1
     
     !pick out diagonal block
     allocate( ttt(icol1:icol2,icol1:icol2), stat = ii )
     if( ii /= 0 ) call alloc_err
     ttt=0._wp
     jvec=0
     n21=0
     do irow=icol1,icol2
      ttt(irow,irow)=diag(irow)
      ksub=xnzsub(irow)
      do i=xlnz(irow),xlnz(irow+1)-1
       jcol=ixsub(ksub)
       ksub=ksub+1
       if(jcol<=icol2)then
        ttt(jcol,irow)=xspars(i) 
       else 
        if(jvec(jcol).eq.0)then
         n21=n21+1
         jvec(jcol)=n21
         kvec(n21)=jcol
        endif
       end if
      end do
     end do

     !pick out lead columns (condensed)
     if( n21 > 0 ) then
         allocate( s21(n21, icol1:icol2), stat = ii )
         if( ii /= 0 ) call alloc_err
         allocate( f21(n21, icol1:icol2), stat = ii )
         if( ii /= 0 ) call alloc_err
         s21 = 0.d0
         f21 = 0.d0
         do irow = icol1, icol2
            ksub = xnzsub(irow)
            do i = xlnz(irow), xlnz(irow+1)-1
               jcol = ixsub(ksub)
               ksub = ksub + 1
               if( jcol <= icol2 ) cycle
               jj = jvec(jcol)
               s21(jj,irow) = xspars(i)
            end do
         end do
!        ... post-multiply with inverse Chol factor -> solve
         call dtrsm( 'R', 'L', 'N', 'N', n21, mm, 1.d0, ttt, mm, s21, n21 )
!        ... invert Cholesky factor
         call dpotri( 'L',  mm, ttt, mm, ii )
         if( ii /= 0 ) then
             write(*,*) 'Routine DPOTRI returned error code', ii
             stop
         end if
!        ... pre-multiply by already inverted submatrix
         iopt = 2
44       if( iopt == 1 ) then
            allocate( rr(icol1:icol2), qx(icol1:icol2), stat = ii )
            if( ii /= 0 ) call alloc_err
            f21 = 0.d0
            do k = 1, n21
               jrow = kvec(k)
               rr = s21(k,:)
               qx =  diag(jrow) * rr 
               ksub = xnzsub(jrow)
               do i = xlnz(jrow), xlnz(jrow+1)-1
                  jcol = ixsub(ksub)
                  ksub = ksub + 1
                  m = jvec(jcol)
                  if( m < 1 ) cycle
                  xx = xspars(i)
                  f21(m,:) = f21(m,:) + xx * rr
                  qx = qx + xx * s21(m,:) 
               end do
               f21(k,:) = f21(k,:) + qx 
            end do
            deallocate( rr, qx )
         else
            allocate( s22(n21,n21), stat = ii )
            if( ii /= 0 ) then
                iopt = 1
                go to 44
            end if
            s22 = 0.d0
            do k = 1, n21
               jrow = kvec(k)
               s22(k,k) = diag(jrow)
               ksub = xnzsub(jrow)
               do i = xlnz(jrow), xlnz(jrow+1)-1
                  jcol = ixsub(ksub)
                  ksub = ksub + 1
                  m = jvec(jcol)
                  if( m > 0 )then
                   if(m>k)then
                    s22(m,k) = xspars(i)
                   else
                    s22(k,m) = xspars(i)
                   endif
                  endif
               end do
            end do
            call dsymm( 'L', 'L', n21, mm, 1.d0, s22, n21, s21, n21, 0.d0,     &
&                                                                f21, n21  )
            deallocate( s22 )
         end if
!        ... adjustments to current block
         call dgemm( 'T', 'N', mm, mm, n21, 1.d0, f21, n21, s21, n21, 1.d0,    &
&                                                                 ttt, mm )
     else
         call dpotri( 'L',  mm, ttt, mm, ii )
         if( ii /= 0 ) then
             write(*,*) 'Routine DPOTRI returned error code', ii
             stop
         end if
     end if

!    save current block  
     do irow = icol1, icol2
        diag(irow) = ttt(irow,irow)
        ksub = xnzsub(irow)
        do i = xlnz(irow), xlnz(irow+1)-1
           jcol = ixsub(ksub)
           ksub = ksub + 1
           if( jcol <= icol2 ) then
               xspars(i) = ttt(jcol,irow) 
           else 
               xspars(i) = - f21(jvec(jcol),irow)
           end if
        end do
     end do
     deallocate( ttt )
     if( n21 > 0 ) deallocate( s21, f21 )
  end do ! jnode

  deallocate( jvec, kvec )

end subroutine 

subroutine computexsparsdiag(neqns,ia,ja,a,xlnz,nzsub,xnzsub,maxlnz,xspars,diag,perm)
 integer(kind=int32),intent(in)::neqns,maxlnz
 integer(kind=int32)::ia(:),ja(:),perm(:),xlnz(:),nzsub(:),xnzsub(:)
 real(kind=wp),intent(in)::a(:)
 real(kind=wp),intent(out),allocatable::xspars(:),diag(:)

 integer(kind=int32)::irow,iirow,icol,i,j,k,kk
 integer(kind=int32),allocatable::tmp(:)
 real(kind=wp),allocatable::rtmp(:)

 allocate(xspars(maxlnz),diag(neqns))
 xspars=0._wp
 diag=0._wp

 do i=1,neqns
  irow=perm(i)
  diag(i)=a(ia(irow))
  do k=xlnz(i),xlnz(i+1)-1
   iirow=irow
   icol=perm(nzsub(xnzsub(i)+k-xlnz(i)))
   if(iirow.gt.icol)then
    iirow=icol
    icol=irow
   endif
   do j=ia(iirow)+1,ia(iirow+1)-1
    if(ja(j).eq.icol)then
     xspars(k)=a(j)
     exit
    endif
   enddo
  enddo
 enddo

end subroutine

subroutine converttoija(neqns,xlnz,xspars,xnzsub,ixsub,diag,ia,ja,a,perm)
 integer(kind=int32),intent(in)::neqns
 integer(kind=int32),intent(in)::ixsub(:),xlnz(:),xnzsub(:)
 integer(kind=int32),intent(in)::ia(:),ja(:),perm(:)
 real(kind=wp),intent(in)::xspars(:),diag(:)
 real(kind=wp),intent(inout):: a(:)

 integer(kind=int32)::irow,ksub,i,icol
 integer(kind=int32)::pirow,ppirow,picol,ip

 do irow = 1, neqns
  pirow=perm(irow)
  a(ia(pirow))=diag(irow)
  ksub = xnzsub(irow)
  do i = xlnz(irow), xlnz(irow+1)-1
   ppirow=pirow
   icol = ixsub(ksub)
   picol=perm(icol)
   ksub = ksub + 1
   if(ppirow.gt.picol)then
    ppirow=picol
    picol=pirow
   endif
   intloop: do ip=ia(ppirow)+1,ia(ppirow+1)-1
    if(ja(ip).eq.picol)then
     a(ip)=xspars(i)
     exit intloop
    endif
   enddo intloop
  end do
 end do

end subroutine 

subroutine alloc_err()
 write(*,'(a,i0,3a)')' ERROR (',__LINE__,',',__FILE__,'): failed allocation'
 error stop
end subroutine 

subroutine writetime(unlog,time,a)
 integer(kind=int32)::unlog
 real(kind=real64),intent(in)::time(:)
 character(len=*),intent(in)::a

 write(unlog,'(/a)')' CRS MATRIX '//trim(a)
 !$ write(unlog,'(2x,a,t31,a,t33,f10.3,a)')'Symbolic factorization',':',time(1),' s'
 !$ write(unlog,'(2x,a,t31,a,t33,f10.3,a)')'Setup of tmp arrays',':',time(2),' s'
 !$ write(unlog,'(2x,a,t31,a,t33,f10.3,a)')'Node determination',':',time(3),' s'
 !$ write(unlog,'(2x,a,t31,a,t33,f10.3,a)')'Cholesky factorization',':',time(4),' s'
 !$ write(unlog,'(2x,a,t31,a,t33,f10.3,a)')'Matrix inversion',':',time(5),' s'
 !$ write(unlog,'(2x,a,t31,a,t33,f10.3,a)')'Conversion to CRS',':',time(6),' s'
 !$ write(unlog,'(2x,a,t31,a,t33,f10.3,a)')'Total time',':',sum(time),' s'

end subroutine

end module
