'use client';
/* eslint-disable @next/next/no-img-element -- Private profile images require the owner's cookies. */
import { useEffect, useState } from 'react';
import { UserRound } from 'lucide-react';

export function ProfileAvatar() {
  const [photo, setPhoto] = useState<string | null>('/api/v1/account/photo');
  useEffect(() => {
    const refresh = () => setPhoto(`/api/v1/account/photo?v=${Date.now()}`);
    window.addEventListener('fintrack-profile-updated', refresh);
    return () => window.removeEventListener('fintrack-profile-updated', refresh);
  }, []);
  return photo ? <img src={photo} alt="" className="size-full rounded-full object-cover" onError={() => setPhoto(null)}/> : <UserRound size={18}/>;
}
