###############################################################################
# app/main.py  –  Banking REST API (FastAPI + PostgreSQL)
###############################################################################
import logging
import os
from contextlib import asynccontextmanager
from decimal import Decimal

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, condecimal
from sqlalchemy import Column, DateTime, Numeric, String, create_engine, func
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import Session, sessionmaker

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger(__name__)

# ── DB Setup ──────────────────────────────────────────────────────────────────
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_NAME = os.environ.get("DB_NAME", "bankingdb")
DB_USER = os.environ.get("DB_USER", "banking_admin")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")
DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:5432/{DB_NAME}"
)

engine = create_engine(DATABASE_URL, pool_pre_ping=True, pool_size=5, max_overflow=10)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class Account(Base):
    __tablename__ = "accounts"
    account_id = Column(String(36), primary_key=True, index=True)
    owner_name = Column(String(255), nullable=False)
    balance = Column(Numeric(18, 2), nullable=False, default=Decimal("0.00"))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(bind=engine)
    logger.info("Database tables created / verified")
    yield


# ── App ───────────────────────────────────────────────────────────────────────
app = FastAPI(
    title="Banking API",
    version="1.0.0",
    docs_url="/docs" if os.getenv("APP_ENV") != "prod" else None,
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://banking.example.com"],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# ── Schemas ───────────────────────────────────────────────────────────────────
class AccountCreate(BaseModel):
    account_id: str
    owner_name: str
    initial_balance: condecimal(ge=0, decimal_places=2) = Decimal("0.00")


class AmountRequest(BaseModel):
    amount: condecimal(gt=0, decimal_places=2)


class AccountResponse(BaseModel):
    account_id: str
    owner_name: str
    balance: Decimal

    class Config:
        from_attributes = True


# ── Helpers ───────────────────────────────────────────────────────────────────
def get_account_or_404(account_id: str, db: Session) -> Account:
    acct = db.query(Account).filter(Account.account_id == account_id).first()
    if not acct:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Account not found"
        )
    return acct


# ── Routes ────────────────────────────────────────────────────────────────────
@app.get("/health")
def health_check():
    return {"status": "ok"}


@app.post("/accounts", response_model=AccountResponse, status_code=201)
def create_account(payload: AccountCreate, db: Session = Depends(get_db)):
    if db.query(Account).filter(Account.account_id == payload.account_id).first():
        raise HTTPException(status_code=409, detail="Account already exists")
    acct = Account(
        account_id=payload.account_id,
        owner_name=payload.owner_name,
        balance=payload.initial_balance,
    )
    db.add(acct)
    db.commit()
    db.refresh(acct)
    logger.info("Account created account_id=%s", acct.account_id)
    return acct


@app.get("/accounts/{account_id}/balance", response_model=AccountResponse)
def get_balance(account_id: str, db: Session = Depends(get_db)):
    return get_account_or_404(account_id, db)


@app.post("/accounts/{account_id}/deposit", response_model=AccountResponse)
def deposit(account_id: str, payload: AmountRequest, db: Session = Depends(get_db)):
    acct = get_account_or_404(account_id, db)
    acct.balance += payload.amount
    db.commit()
    db.refresh(acct)
    logger.info(
        "DEPOSIT account_id=%s amount=%s new_balance=%s",
        account_id,
        payload.amount,
        acct.balance,
    )
    return acct


@app.post("/accounts/{account_id}/withdraw", response_model=AccountResponse)
def withdraw(account_id: str, payload: AmountRequest, db: Session = Depends(get_db)):
    acct = get_account_or_404(account_id, db)
    if payload.amount < 0:
        logger.wa
    if acct.balance < payload.amount:
        logger.warning(
            "TRANSACTION_FAILED account_id=%s reason=insufficient_funds", account_id
        )
        raise HTTPException(status_code=422, detail="Insufficient funds")
    acct.balance -= payload.amount
    db.commit()
    db.refresh(acct)
    logger.info(
        "WITHDRAW account_id=%s amount=%s new_balance=%s",
        account_id,
        payload.amount,
        acct.balance,
    )
    return acct

@app.get("/accounts/all", response_model=list[AccountResponse])
def list_accounts(db: Session = Depends(get_db)):
    logger.info(
        "DEPOSIT account_id=%s amount=%s new_balance=%s",
        account_id,
        payload.amount,
        acct.balance,
    )
    return db.query(Account).all()  
