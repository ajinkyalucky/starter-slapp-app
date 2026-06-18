import { useState, useEffect, useRef } from 'react'
import './App.css'

// ── Splash ────────────────────────────────────────────────────────────────────

function SplashScreen({ onNext }) {
  useEffect(() => {
    const t = setTimeout(onNext, 2200)
    return () => clearTimeout(t)
  }, [onNext])

  return (
    <div className="screen splash">
      <div className="buji-logo">BUJi</div>
    </div>
  )
}

// ── Phone entry ───────────────────────────────────────────────────────────────

function PhoneScreen({ onNext }) {
  const [phone, setPhone] = useState('')

  const handleKey = (key) => {
    if (key === 'del') setPhone(p => p.slice(0, -1))
    else if (phone.length < 10) setPhone(p => p + key)
  }

  const formatted = phone.replace(/(\d{5})(\d{0,5})/, (_, a, b) => b ? `${a} ${b}` : a)
  const canProceed = phone.length === 10

  return (
    <div className="screen white">
      <ProgressBar step={1} total={2} labels={['about you', 'about your fit']} />
      <div className="content">
        <h1 className="heading">
          enter your<br />mobile number
        </h1>
        <div className="phone-input-box">
          <span className="prefix">+91</span>
          <span className="phone-value">
            {formatted || <span className="placeholder-text">XXXXX XXXXX</span>}
          </span>
          <span className="cursor blink" />
        </div>
        <p className="disclaimer">
          By logging in, you agree to DRIP's{' '}
          <span className="link">Terms and Conditions.</span>
        </p>
        <button
          className={`proceed-btn ${canProceed ? 'active' : ''}`}
          onClick={() => canProceed && onNext(phone)}
        >
          PROCEED
        </button>
      </div>
      <Numpad onKey={handleKey} />
    </div>
  )
}

// ── OTP ───────────────────────────────────────────────────────────────────────

function OtpScreen({ phone, onNext, onBack }) {
  const [otp, setOtp] = useState(['', '', '', ''])
  const [timer, setTimer] = useState(28)
  const [shake, setShake] = useState(false)

  useEffect(() => {
    if (timer === 0) return
    const t = setInterval(() => setTimer(s => s - 1), 1000)
    return () => clearInterval(t)
  }, [timer])

  const handleKey = (key) => {
    if (key === 'del') {
      const last = [...otp].map((v, i) => v !== '' ? i : -1).filter(i => i !== -1).pop()
      if (last === undefined) return
      setOtp(o => { const n = [...o]; n[last] = ''; return n })
      return
    }
    const idx = otp.findIndex(v => v === '')
    if (idx === -1) return
    const next = [...otp]; next[idx] = key; setOtp(next)
    if (next.every(v => v !== '') && next.join('') !== '1234') {
      setTimeout(() => {
        setShake(true)
        setTimeout(() => { setShake(false); setOtp(['', '', '', '']) }, 600)
      }, 100)
    }
  }

  const filledCount = otp.filter(v => v !== '').length
  const canProceed = filledCount === 4 && !shake
  const masked = `+91 70${phone.slice(2, 5).split('').map(() => 'X').join('')} XXX${phone.slice(-2)}`

  return (
    <div className="screen white">
      <div className="back-row">
        <button className="back-btn" onClick={onBack}>←</button>
      </div>
      <ProgressBar step={1} total={2} labels={['Personal details', 'Fit details']} />
      <div className="content">
        <h1 className="heading">
          enter the<br />4 digit code
        </h1>
        <p className="otp-sent">
          OTP sent to {masked}{' '}
          <span className="link" onClick={onBack}>Change</span>
        </p>
        <div className={`otp-boxes ${shake ? 'shake' : ''}`}>
          {otp.map((v, i) => (
            <div key={i} className={`otp-box ${v ? 'filled' : ''} ${i === filledCount && !shake ? 'active' : ''}`}>
              {v}
            </div>
          ))}
        </div>
        <p className="resend-row">
          {timer > 0
            ? <span>Resend in 00:{String(timer).padStart(2, '0')} <span className="resend-inactive">Resend</span></span>
            : <><span>Didn't receive? </span><span className="link" onClick={() => { setTimer(28); setOtp(['','','','']) }}>Resend</span></>
          }
        </p>
        <p className="otp-hint">(hint: use 1234)</p>
        <button
          className={`proceed-btn ${canProceed ? 'active' : ''}`}
          onClick={() => canProceed && onNext()}
        >
          PROCEED
        </button>
      </div>
      <Numpad onKey={handleKey} />
    </div>
  )
}

// ── About You ─────────────────────────────────────────────────────────────────

function AboutYouScreen({ onNext }) {
  const [name, setName] = useState('')
  const [gender, setGender] = useState('')
  const [dob, setDob] = useState('')

  const canProceed = name.trim() && gender && dob.length >= 8

  return (
    <div className="screen white">
      <ProgressBar step={1} total={2} labels={['Personal details', 'Fit details']} />
      <div className="content form-content">
        <h1 className="heading">about you</h1>

        <div className="form-group">
          <label>Full name</label>
          <input
            className="text-input"
            placeholder="Enter your name"
            value={name}
            onChange={e => setName(e.target.value)}
          />
        </div>

        <div className="form-group">
          <label>Date of birth</label>
          <input
            className="text-input"
            placeholder="DD / MM / YYYY"
            value={dob}
            onChange={e => {
              let v = e.target.value.replace(/\D/g, '')
              if (v.length > 2) v = v.slice(0,2) + ' / ' + v.slice(2)
              if (v.length > 8) v = v.slice(0,8) + ' / ' + v.slice(8,12)
              setDob(v.slice(0,14))
            }}
            maxLength={14}
          />
        </div>

        <div className="form-group">
          <label>Gender</label>
          <div className="chip-row">
            {['Male', 'Female', 'Other'].map(g => (
              <button key={g} className={`chip ${gender === g ? 'selected' : ''}`} onClick={() => setGender(g)}>
                {g}
              </button>
            ))}
          </div>
        </div>

        <button className={`proceed-btn ${canProceed ? 'active' : ''}`} onClick={() => canProceed && onNext()}>
          PROCEED
        </button>
      </div>
    </div>
  )
}

// ── About Fit ─────────────────────────────────────────────────────────────────

function AboutFitScreen({ onNext, onBack }) {
  const [height, setHeight] = useState('')
  const [weight, setWeight] = useState('')
  const [build, setBuild] = useState('')

  const canProceed = height && weight && build

  return (
    <div className="screen white">
      <div className="back-row">
        <button className="back-btn" onClick={onBack}>←</button>
      </div>
      <ProgressBar step={2} total={2} labels={['Personal details', 'Fit details']} />
      <div className="content form-content">
        <h1 className="heading">about your fit</h1>

        <div className="form-group">
          <label>Height</label>
          <div className="unit-row">
            <input
              className="text-input"
              placeholder="e.g. 175"
              value={height}
              onChange={e => setHeight(e.target.value.replace(/\D/g, '').slice(0,3))}
              type="text"
              inputMode="numeric"
            />
            <span className="unit">cm</span>
          </div>
        </div>

        <div className="form-group">
          <label>Weight</label>
          <div className="unit-row">
            <input
              className="text-input"
              placeholder="e.g. 70"
              value={weight}
              onChange={e => setWeight(e.target.value.replace(/\D/g, '').slice(0,3))}
              type="text"
              inputMode="numeric"
            />
            <span className="unit">kg</span>
          </div>
        </div>

        <div className="form-group">
          <label>Body build</label>
          <div className="chip-row wrap">
            {['Slim', 'Athletic', 'Regular', 'Plus'].map(b => (
              <button key={b} className={`chip ${build === b ? 'selected' : ''}`} onClick={() => setBuild(b)}>
                {b}
              </button>
            ))}
          </div>
        </div>

        <button className={`proceed-btn ${canProceed ? 'active' : ''}`} onClick={() => canProceed && onNext()}>
          GET STARTED
        </button>
      </div>
    </div>
  )
}

// ── Success ───────────────────────────────────────────────────────────────────

function SuccessScreen({ onRestart }) {
  return (
    <div className="screen splash">
      <div className="success-wrap">
        <div className="check-circle">✓</div>
        <p className="success-title">You&rsquo;re all set!</p>
        <p className="success-sub">Welcome to BUJi</p>
        <button className="proceed-btn active" style={{ width: 280, marginTop: 40 }} onClick={onRestart}>
          START SHOPPING
        </button>
      </div>
    </div>
  )
}

// ── Shared ────────────────────────────────────────────────────────────────────

function ProgressBar({ step, total, labels }) {
  return (
    <div className="progress-wrap">
      {Array.from({ length: total }).map((_, i) => (
        <div key={i} className="progress-col">
          <div className={`progress-bar ${i < step ? 'done' : ''}`} />
          <span className="progress-label">{labels[i]}</span>
        </div>
      ))}
    </div>
  )
}

function Numpad({ onKey }) {
  const rows = [['1','2','3'],['4','5','6'],['7','8','9'],['','0','del']]
  const subs = { '2':'ABC','3':'DEF','4':'GHI','5':'JKL','6':'MNO','7':'PQRS','8':'TUV','9':'WXYZ' }

  return (
    <div className="numpad">
      {rows.map((row, ri) => (
        <div key={ri} className="numpad-row">
          {row.map((k, ki) => (
            k === '' ? <div key={ki} className="key empty" /> :
            k === 'del' ? (
              <button key={ki} className="key del-key" onClick={() => onKey('del')}>⌫</button>
            ) : (
              <button key={ki} className="key" onClick={() => onKey(k)}>
                <span className="key-num">{k}</span>
                {subs[k] && <span className="key-sub">{subs[k]}</span>}
              </button>
            )
          ))}
        </div>
      ))}
    </div>
  )
}

function StatusBar() {
  const [time, setTime] = useState(() => new Date())
  useEffect(() => {
    const t = setInterval(() => setTime(new Date()), 1000)
    return () => clearInterval(t)
  }, [])
  const h = time.getHours(), m = time.getMinutes()
  return (
    <div className="status-bar">
      <span className="status-time">{String(h).padStart(2,'0')}:{String(m).padStart(2,'0')}</span>
      <div className="status-icons">
        <svg width="17" height="12" viewBox="0 0 17 12"><rect x="0" y="4" width="3" height="8" rx="1" fill="currentColor"/><rect x="4.5" y="2.5" width="3" height="9.5" rx="1" fill="currentColor"/><rect x="9" y="0.5" width="3" height="11.5" rx="1" fill="currentColor"/><rect x="13.5" y="0" width="3" height="12" rx="1" fill="none" stroke="currentColor" strokeWidth="1"/></svg>
        <svg width="16" height="12" viewBox="0 0 16 12"><path d="M8 3C5.6 3 3.4 4 1.8 5.7L0 3.8C2.1 1.7 4.9 0.5 8 0.5s5.9 1.2 8 3.3L14.2 5.7C12.6 4 10.4 3 8 3z" fill="currentColor"/><path d="M8 6.5c-1.5 0-2.8.6-3.8 1.5L2.5 6.3C3.9 5 5.9 4.2 8 4.2s4.1.8 5.5 2.1L11.8 8C10.8 7.1 9.5 6.5 8 6.5z" fill="currentColor"/><circle cx="8" cy="11" r="1.5" fill="currentColor"/></svg>
        <svg width="25" height="12" viewBox="0 0 25 12"><rect x="0" y="1" width="22" height="10" rx="2" stroke="currentColor" strokeWidth="1.2" fill="none"/><rect x="1.5" y="2.5" width="17" height="7" rx="1" fill="currentColor"/><path d="M23 4v4a2 2 0 000-4z" fill="currentColor"/></svg>
      </div>
    </div>
  )
}

// ── Root ──────────────────────────────────────────────────────────────────────

export default function App() {
  const [screen, setScreen] = useState('splash')
  const [phone, setPhone] = useState('')

  return (
    <div className="phone-shell">
      <StatusBar />
      <div className="screen-area">
        {screen === 'splash'    && <SplashScreen onNext={() => setScreen('phone')} />}
        {screen === 'phone'     && <PhoneScreen onNext={p => { setPhone(p); setScreen('otp') }} />}
        {screen === 'otp'       && <OtpScreen phone={phone} onNext={() => setScreen('about-you')} onBack={() => setScreen('phone')} />}
        {screen === 'about-you' && <AboutYouScreen onNext={() => setScreen('about-fit')} />}
        {screen === 'about-fit' && <AboutFitScreen onNext={() => setScreen('success')} onBack={() => setScreen('about-you')} />}
        {screen === 'success'   && <SuccessScreen onRestart={() => { setPhone(''); setScreen('splash') }} />}
      </div>
      <div className="home-bar" />
    </div>
  )
}
